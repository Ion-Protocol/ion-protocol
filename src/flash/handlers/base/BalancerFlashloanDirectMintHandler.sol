// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandlerBase } from "./IonHandlerBase.sol";

import { IVault, IERC20 as IERC20Balancer } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

IVault constant VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

/**
 * @dev There a couple things to consider here from a security perspective. The
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

    error ReceiveCallerNotVault(address unauthorizedCaller);
    error FlashLoanedTooManyTokens(uint256 amountTokens);
    error FlashloanedInvalidToken(address tokenAddress);
    error ExternalBalancerFlashloanNotAllowed();

    uint256 private flashloanInitiated = 1;

    /**
     * @notice Code assumes Balancer flashloans remain free
     * @param initialDeposit in collateral terms
     * @param resultingAdditionalCollateral in collateral terms
     * @param maxResultingDebt in WETH terms. This is not a bound since lst mints
     * do not incur slippage.
     */
    function flashLeverageCollateral(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt
    )
        external
    {
        lstToken.safeTransferFrom(msg.sender, address(this), initialDeposit);

        uint256 amountToLeverage = resultingAdditionalCollateral - initialDeposit; // in collateral terms

        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(lstToken));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountToLeverage;

        uint256 wethRequiredForRepayment = _getEthAmountInForLstAmountOut(amountToLeverage);
        if (wethRequiredForRepayment > maxResultingDebt) {
            revert FlashloanRepaymentTooExpensive(wethRequiredForRepayment, maxResultingDebt);
        }

        // Prevents attacked from initiating flashloan and passing malicious data through callback
        flashloanInitiated = 2;

        VAULT.flashLoan(
            IFlashLoanRecipient(address(this)),
            addresses,
            amounts,
            abi.encode(msg.sender, initialDeposit, resultingAdditionalCollateral, maxResultingDebt)
        );

        flashloanInitiated = 1;
    }

    /**
     * @notice Code assumes Balancer flashloans remain free
     * @param initialDeposit in collateral terms
     * @param resultingAdditionalCollateral in collateral terms
     * @param maxResultingDebt in WETH terms. This is not a bound since lst mints
     * do not incur slippage. However, `maxResultingDebt` weth will be used to mint
     * the lst, and the outputted lst amount should match the
     * `resultingAdditionalCollateral` value.
     */
    function flashLeverageWeth(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt
    )
        external
        payable
    {
        lstToken.safeTransferFrom(msg.sender, address(this), initialDeposit);

        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(weth));

        uint256 amountLst = resultingAdditionalCollateral - initialDeposit; // in collateral terms
        uint256 amountWethToFlashloan = _getEthAmountInForLstAmountOut(amountLst);

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
            abi.encode(msg.sender, initialDeposit, resultingAdditionalCollateral, maxResultingDebt)
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
        (address user, uint256 initialDeposit, uint256 resultingAdditionalCollateral, uint256 maxResultingDebt) =
            abi.decode(userData, (address, uint256, uint256, uint256));

        if (maxResultingDebt == 0) {
            // AmountToBorrow.IS_MAX because we don't want to create any new debt here
            _depositAndBorrow(user, address(this), resultingAdditionalCollateral, 0, AmountToBorrow.IS_MAX);
            return;
        }

        // Flashloaned WETH needs to be converted into collateral asset
        if (address(token) == address(weth)) {
            uint256 collateralFromDeposit = _depositWethForLst(amounts[0]);

            // Sanity checks
            assert(collateralFromDeposit + initialDeposit == resultingAdditionalCollateral);
            assert(collateralFromDeposit <= maxResultingDebt);

            // AmountToBorrow.IS_MIN because we want to make sure enough is borrowed to cover flashloan
            _depositAndBorrow(user, address(this), resultingAdditionalCollateral, amounts[0], AmountToBorrow.IS_MIN);

            weth.transfer(address(VAULT), amounts[0]);
        } else {
            if (address(lstToken) != address(token)) revert FlashloanedInvalidToken(address(token));

            uint256 wethToBorrow = _getEthAmountInForLstAmountOut(amounts[0]);

            // Sanity checks
            assert(amounts[0] + initialDeposit == resultingAdditionalCollateral);
            assert(wethToBorrow <= maxResultingDebt);

            // AmountToBorrow.IS_MIN because we want to make sure enough is borrowed to cover flashloan
            _depositAndBorrow(user, address(this), resultingAdditionalCollateral, wethToBorrow, AmountToBorrow.IS_MIN);

            // Convert borrowed WETH back to collateral token
            uint256 tokenAmountReceived = _depositWethForLst(maxResultingDebt);

            lstToken.safeTransfer(address(VAULT), tokenAmountReceived);
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
