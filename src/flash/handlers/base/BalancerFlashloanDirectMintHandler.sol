// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandlerBase } from "./IonHandlerBase.sol";
import { IWETH9 } from "../../../interfaces/IWETH9.sol";

import { IVault, IERC20 as IERC20Balancer } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

IVault constant VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

/**
 * @dev There are a couple things to consider here from a security perspective. The
 * first one is that the flashloan callback must only be callable from the
 * Balancer vault. This ensures that nobody can pass arbitrary data to the
 * callback. The second one is that the flashloan must only be initialized from
 * this contract. This is a trickier one to enforce since Balancer flashloans
 * are not EIP-3156 compliant and do not pass on the initiator through the
 * callback. To get around this, an inverse reentrancy lock of sorts is used.
 * The lock is set to 2 when a flashloan is initiated and set to 1 once the
 * callback execution terminates. If the lock is not 2 when the callback is
 * called, then the flashloan was not initiated by this contract and the tx is
 * reverted.
 *
 * This contract currently deposits directly into LST contract 1:1. It should be
 * noted that a more favorable trade could be possible via DEXs.
 */
abstract contract BalancerFlashloanDirectMintHandler is IonHandlerBase, IFlashLoanRecipient {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH9;

    error ReceiveCallerNotVault(address unauthorizedCaller);
    error FlashLoanedTooManyTokens(uint256 amountTokens);
    error FlashloanedInvalidToken(address tokenAddress);
    error ExternalBalancerFlashloanNotAllowed();

    uint256 private flashloanInitiated = 1;

    /**
     * @notice Code assumes Balancer flashloans remain free
     * @param initialDeposit in collateral terms
     * @param resultingAdditionalCollateral in collateral terms
     * @param maxResultingDebt in WETH terms. While it is unlikely that the
     * exchange rate changes from when a transaction is submitted versus when it
     * is executed, it is still possible so we want to allow for a bound here,
     * even though it doesn't pose the same level of threat as slippage.
     */
    function flashLeverageCollateral(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt,
        bytes32[] memory proof
    )
        external
        onlyWhitelistedBorrowers(proof)
    {
        LST_TOKEN.safeTransferFrom(msg.sender, address(this), initialDeposit);
        _flashLeverageCollateral(initialDeposit, resultingAdditionalCollateral, maxResultingDebt);
    }

    /**
     * @dev Assumes that the caller has already transferred the deposit asset. Can be called internally by a wrapper
     * that needs additional logic
     * to obtain the LST. Ex) Zapping stEth to wstEth.
     */
    function _flashLeverageCollateral(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt
    )
        internal
    {
        uint256 amountToLeverage = resultingAdditionalCollateral - initialDeposit; // in collateral terms

        if (amountToLeverage == 0) {
            // AmountToBorrow.IS_MAX because we don't want to create any new debt here
            _depositAndBorrow(msg.sender, address(this), resultingAdditionalCollateral, 0, AmountToBorrow.IS_MAX);
            return;
        }

        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(LST_TOKEN));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountToLeverage;

        uint256 wethRequiredForRepayment = _getEthAmountInForLstAmountOut(amountToLeverage);
        if (wethRequiredForRepayment > maxResultingDebt) {
            revert FlashloanRepaymentTooExpensive(wethRequiredForRepayment, maxResultingDebt);
        }

        // Prevents attackers from initiating flashloan and passing malicious data through callback
        flashloanInitiated = 2;

        VAULT.flashLoan(
            IFlashLoanRecipient(address(this)),
            addresses,
            amounts,
            abi.encode(msg.sender, initialDeposit, resultingAdditionalCollateral)
        );

        flashloanInitiated = 1;
    }

    /**
     * @notice Code assumes Balancer flashloans remain free
     * @param initialDeposit in collateral terms
     * @param resultingAdditionalCollateral in collateral terms
     * @param maxResultingDebt in WETH terms. While it is unlikely that the
     * exchange rate changes from when a transaction is submitted versus when it
     * is executed, it is still possible so we want to allow for a bound here,
     * even though it doesn't pose the same level of threat as slippage.
     */
    function flashLeverageWeth(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt,
        bytes32[] memory proof
    )
        external
        payable
        onlyWhitelistedBorrowers(proof)
    {
        LST_TOKEN.safeTransferFrom(msg.sender, address(this), initialDeposit);
        _flashLeverageWeth(initialDeposit, resultingAdditionalCollateral, maxResultingDebt);
    }

    /**
     * @dev Assumes that the caller has already transferred the deposit asset. Can be called internally by a wrapper
     * that needs additional logic
     * to obtain the LST. Ex) Zapping stEth to wstEth.
     */
    function _flashLeverageWeth(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt
    )
        internal
    {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(WETH));

        uint256 amountLst = resultingAdditionalCollateral - initialDeposit; // in collateral terms
        uint256 amountWethToFlashloan = _getEthAmountInForLstAmountOut(amountLst);

        if (amountWethToFlashloan == 0) {
            // AmountToBorrow.IS_MAX because we don't want to create any new debt here
            _depositAndBorrow(msg.sender, address(this), resultingAdditionalCollateral, 0, AmountToBorrow.IS_MAX);
            return;
        }

        // It is technically possible to accrue slight dust amounts more of debt
        // than maxResultingDebt because you may need to borrow slightly more at
        // the IonPool level to receieve the desired amount of WETH. This is
        // because the IonPool will round in its favor and always gives out dust
        // amounts less of WETH than the debt accrued to the position. However,
        // this will always be bounded by the rate of the ilk at the time
        // divided by RAY and will NEVER be subject to slippage, which is what
        // we really want to protect against.
        if (amountWethToFlashloan > maxResultingDebt) {
            revert FlashloanRepaymentTooExpensive(amountWethToFlashloan, maxResultingDebt);
        }

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountWethToFlashloan;

        flashloanInitiated = 2;

        VAULT.flashLoan(
            IFlashLoanRecipient(address(this)),
            addresses,
            amounts,
            abi.encode(msg.sender, initialDeposit, resultingAdditionalCollateral)
        );

        flashloanInitiated = 1;
    }

    /**
     * @notice Code assumes Balancer flashloans remain free.
     * @dev This function is intended to never be called directly. It should
     * only be called by the Balancer VAULT during a flashloan initiated by this
     * contract. This callback logic only handles the creation of leverage
     * positions by minting. Since not all tokens have withdrawable liquidity
     * via the LST protocol directly, deleverage through the protocol will need
     * to be implemented in the inheriting contract.
     *
     * @param tokens Array of tokens flash loaned
     * @param amounts amounts flash loaned
     * @param userData arbitrary data passed from initiator of flash loan
     */
    function receiveFlashLoan(
        IERC20Balancer[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory,
        bytes memory userData
    )
        external
        override
    {
        if (tokens.length > 1) revert FlashLoanedTooManyTokens(tokens.length);
        if (msg.sender != address(VAULT)) revert ReceiveCallerNotVault(msg.sender);
        if (flashloanInitiated != 2) revert ExternalBalancerFlashloanNotAllowed();

        IERC20Balancer token = tokens[0];
        (address user, uint256 initialDeposit, uint256 resultingAdditionalCollateral) =
            abi.decode(userData, (address, uint256, uint256));

        // Flashloaned WETH needs to be converted into collateral asset
        if (address(token) == address(WETH)) {
            uint256 collateralFromDeposit = _depositWethForLst(amounts[0]);

            // Sanity checks
            assert(collateralFromDeposit + initialDeposit == resultingAdditionalCollateral);

            // AmountToBorrow.IS_MIN because we want to make sure enough is borrowed to cover flashloan
            _depositAndBorrow(user, address(this), resultingAdditionalCollateral, amounts[0], AmountToBorrow.IS_MIN);

            WETH.safeTransfer(address(VAULT), amounts[0]);
        } else {
            if (address(LST_TOKEN) != address(token)) revert FlashloanedInvalidToken(address(token));

            uint256 wethToBorrow = _getEthAmountInForLstAmountOut(amounts[0]);

            // Sanity checks
            assert(amounts[0] + initialDeposit == resultingAdditionalCollateral);

            // AmountToBorrow.IS_MIN because we want to make sure enough is borrowed to cover flashloan
            _depositAndBorrow(user, address(this), resultingAdditionalCollateral, wethToBorrow, AmountToBorrow.IS_MIN);

            // Convert borrowed WETH back to collateral token
            uint256 tokenAmountReceived = _depositWethForLst(wethToBorrow);

            LST_TOKEN.safeTransfer(address(VAULT), tokenAmountReceived);
        }
    }

    /**
     * @dev Unwraps weth into eth and deposits into lst contract
     * @param amountWeth to deposit
     * @return amountLst received
     */
    function _depositWethForLst(uint256 amountWeth) internal virtual returns (uint256);

    function _getEthAmountInForLstAmountOut(uint256 amountLst) internal view virtual returns (uint256);
}
