// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../IonPool.sol";
import { IonRegistry } from "./../../IonRegistry.sol";
import { IWETH9 } from "../../../interfaces/IWETH9.sol";
import { GemJoin } from "../../../join/GemJoin.sol";

import { IVault, IERC20 } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";

import { IERC20 as IERC20OZ } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

/**
 * @dev There a couple things to consider here from a security perspective. The
 * first one is that the flashloan callback must only be callable from the
 * Balancer vault. This ensures that nobody can pass arbitrary data to the
 * callback from initiating a separate flashloan. The second one is that the
 * flashloan must only be initialized from this contract. This is a trickier one
 * to enforce since Balancer flashloans are not EIP-3156 compliant and do not
 * pass on the initiator through the callback. To get around this, an inverse
 * reentrancy lock of sorts is used. The lock is set to 2 when a flashloan is initiated
 * and set to 1 once the callback execution terminates. If the lock is not 2
 * when the callback is called, then the flashloan was not initiated by this
 * contract and the tx is reverted.
 *
 * This contract currently deposits directly into LST contract 1:1. It should be
 * noted that a more favorable trade could be possible via DEXs.
 */
abstract contract IonHandlerBase is IFlashLoanRecipient {
    using SafeERC20 for IERC20OZ;

    error InvalidFactoryAddress();
    error InvalidSwEthPoolAddress();

    error ReceiveCallerNotVault();
    error FlashLoanedTooManyTokens();
    error FlashLoanedInvalidToken();
    error InsufficientLiquidityForFlashloan();
    error ExternalFlashloanNotAllowed();
    error CannotSendEthToContract();
    error SwapNotAvailableForIlk();

    IWETH9 immutable weth;

    IVault internal constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    IonPool immutable ionPool;
    IonRegistry immutable ionRegistry;
    uint8 immutable ilkIndex;
    IERC20 immutable lstToken;

    uint256 flashLoanInitiated = 1;

    constructor(uint8 _ilkIndex, IonPool _ionPool, IonRegistry _ionRegistry) {
        ionPool = _ionPool;
        ionRegistry = _ionRegistry;
        ilkIndex = _ilkIndex;

        IWETH9 _weth = IWETH9(address(ionPool.underlying()));
        weth = _weth;

        address ilkAddress = ionPool.getIlkAddress(_ilkIndex);
        lstToken = IERC20(ilkAddress);

        _weth.approve(address(ionPool), type(uint256).max);
        IERC20(ilkAddress).approve(address(ionRegistry.gemJoins(_ilkIndex)), type(uint256).max);
    }

    /**
     * @notice Code assumes Balancer flashloans remain free
     * @param initialDeposit in collateral terms
     * @param resultingCollateral in collateral terms
     * @param resultingDebt in WETH terms. This is not a bound since lst mints
     * do not incur slippage.
     */
    function flashLeverageCollateral(
        uint256 initialDeposit,
        uint256 resultingCollateral,
        uint256 resultingDebt
    )
        external
    {
        uint256 amountToLeverage = resultingCollateral - initialDeposit; // in collateral terms

        IERC20[] memory addresses = new IERC20[](1);
        addresses[0] = lstToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amountToLeverage;

        lstToken.transferFrom(msg.sender, address(this), initialDeposit);

        // Prevents attacked from initiating flashloan and passing malicious data through callback
        flashLoanInitiated = 2;

        vault.flashLoan(
            IFlashLoanRecipient(address(this)),
            addresses,
            amounts,
            abi.encode(msg.sender, initialDeposit, resultingCollateral, resultingDebt)
        );

        flashLoanInitiated = 1;
    }

    /**
     * @notice Code assumes Balancer flashloans remain free
     * @param initialDeposit in collateral terms
     * @param resultingCollateral in collateral terms
     * @param resultingDebt in WETH terms. This is not a bound since lst mints
     * do not incur slippage.
     */
    function flashLeverageWeth(
        uint256 initialDeposit,
        uint256 resultingCollateral,
        uint256 resultingDebt
    )
        external
        payable
    {
        IERC20[] memory addresses = new IERC20[](1);
        addresses[0] = IERC20(address(weth));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = resultingDebt;

        lstToken.transferFrom(msg.sender, address(this), initialDeposit);

        flashLoanInitiated = 2;

        vault.flashLoan(
            IFlashLoanRecipient(address(this)),
            addresses,
            amounts,
            abi.encode(msg.sender, initialDeposit, resultingCollateral, resultingDebt)
        );

        flashLoanInitiated = 1;
    }

    /**
     * @notice Code assumes Balancer flashloans remain free.
     * @dev This function is intended to never be called directly. It should
     * only be called by the Balancer vault during a flashloan initiated by this
     * contract. This callback logic only handles the creation of leverage
     * positions by minting. Since not all tokens have withdrawable liquidity
     * via the LST protocol directly, deleverage through the protocol will need to be
     * implemented in the inheriting contract.
     *
     * @param tokens Array of tokens flash loaned
     * @param amounts amounts flash loaned
     * @param userData arbitrary data passed from initiator of flash loan
     */
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory,
        bytes memory userData
    )
        external
        override
    {
        if (flashLoanInitiated != 2) revert ExternalFlashloanNotAllowed();
        if (msg.sender != address(vault)) revert ReceiveCallerNotVault();
        if (tokens.length > 1) revert FlashLoanedTooManyTokens();

        IERC20 token = tokens[0];
        (address user, uint256 initialDeposit, uint256 resultingCollateral, uint256 resultingDebt) =
            abi.decode(userData, (address, uint256, uint256, uint256));

        if (resultingDebt == 0) {
            _depositAndBorrow(user, address(this), resultingCollateral, 0);
            return;
        }

        // Flashloaned WETH needs to be wrapped into collateral asset
        if (address(token) == address(weth)) {
            uint256 collateralFromDeposit = _depositWethForLst(amounts[0]);

            // Sanity check
            assert(collateralFromDeposit + initialDeposit == resultingCollateral);

            _depositAndBorrow(user, address(this), resultingCollateral, resultingDebt);

            weth.transfer(address(vault), amounts[0]);
        } else {
            // Sanity check
            assert(amounts[0] + initialDeposit == resultingCollateral);

            if (address(lstToken) != address(token)) revert FlashLoanedInvalidToken();

            _depositAndBorrow(user, address(this), resultingCollateral, resultingDebt);

            uint256 tokenAmountReceived = _depositWethForLst(resultingDebt);
            // Convert borrowed WETH back to collateral token

            IERC20(lstToken).transfer(address(vault), tokenAmountReceived);
        }
    }

    function depositAndBorrow(uint256 amountCollateral, uint256 amountToBorrow) external {
        lstToken.transferFrom(msg.sender, address(this), amountCollateral);
        _depositAndBorrow(msg.sender, msg.sender, amountCollateral, amountToBorrow);
    }

    /**
     *
     * @param vaultHolder the user who will be responsible for repaying debt
     * @param receiver the user who receives the borrowed funds
     * @param amountCollateral to move into vault
     * @param amountToBorrow out of the vault
     */
    function _depositAndBorrow(
        address vaultHolder,
        address receiver,
        uint256 amountCollateral,
        uint256 amountToBorrow
    )
        internal
    {
        GemJoin gemJoin = GemJoin(ionRegistry.gemJoins(ilkIndex));
        gemJoin.join(address(this), amountCollateral);

        ionPool.moveGemToVault(ilkIndex, vaultHolder, address(this), amountCollateral);

        if (amountToBorrow != 0) ionPool.borrow(ilkIndex, vaultHolder, receiver, amountToBorrow);
    }

    function repayAndWithdraw(uint256 collateralToWithdraw, uint256 debtToRepay) external {
        lstToken.transferFrom(msg.sender, address(this), collateralToWithdraw);
        _repayAndWithdraw(msg.sender, msg.sender, collateralToWithdraw, debtToRepay);
    }

    function _repayAndWithdraw(
        address vaultHolder,
        address receiver,
        uint256 collateralToWithdraw,
        uint256 debtToRepay
    )
        internal
    {
        ionPool.repay(ilkIndex, vaultHolder, address(this), debtToRepay);

        ionPool.moveGemFromVault(ilkIndex, vaultHolder, address(this), collateralToWithdraw);

        GemJoin gemJoin = GemJoin(ionRegistry.gemJoins(ilkIndex));
        gemJoin.exit(receiver, collateralToWithdraw);
    }

    /**
     * @dev Returns how much lst one would get out of a deposit size of
     * `amountWeth`
     */
    function _getLstAmountOut(uint256 amountWeth) internal view virtual returns (uint256);

    /**
     * @dev Unwraps weth into eth and deposits into lst contract
     * @param amountWeth to deposit
     * @return amountLst received
     */
    function _depositWethForLst(uint256 amountWeth) internal virtual returns (uint256);

    receive() external payable {
        if (msg.sender != address(weth)) revert CannotSendEthToContract();
    }
}
