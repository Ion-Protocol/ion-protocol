// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../IonPool.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { IWETH9 } from "../interfaces/IWETH9.sol";
import { IVault, IERC20 } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";
import { IonRegistry } from "./IonRegistry.sol";
import { GemJoin } from "../join/GemJoin.sol";
import {
    ILidoStEthDeposit, ILidoWStEthDeposit, IStaderDeposit, ISwellDeposit
} from "../interfaces/DepositInterfaces.sol";
import { IERC20 as IERC20OZ } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
contract IonHandler is IFlashLoanRecipient {
    using SafeERC20 for IERC20OZ;

    error ReceiveCallerNotVault();
    error FlashLoanedTooManyTokens();
    error FlashLoanedInvalidToken();
    error InsufficientLiquidityForFlashloan();
    error ExternalFlashloanNotAllowed();
    error CannotSendEthToContract();
    error WstEthDepositFailed();

    IonPool immutable ionPool;
    IonRegistry immutable ionRegistry;
    // IERC20 import from Balancer, not from OpenZeppelin
    IWETH9 immutable weth;

    IVault internal constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    uint256 flashLoanInitiated = 1;

    constructor(IonPool _ionPool, IonRegistry _ionRegistry) {
        ionPool = _ionPool;
        ionRegistry = _ionRegistry;

        IWETH9 _weth = IWETH9(address(ionPool.underlying()));
        weth = _weth;

        _weth.approve(address(ionPool), type(uint256).max);

        for (uint8 i = 0; i < ionPool.ilkCount();) {
            IERC20(ionPool.getIlkAddress(i)).approve(address(ionPool), type(uint256).max);
            IERC20(ionPool.getIlkAddress(i)).approve(address(ionRegistry.depositContracts(i)), type(uint256).max);
            IERC20(ionPool.getIlkAddress(i)).approve(address(ionRegistry.gemJoins(i)), type(uint256).max);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Code assumes Balancer flashloans remain free
     * @param ilkIndex of the collateral
     * @param depositAmount in WETH terms
     * @param leverageAmount in WETH terms
     */
    function flashLeverageCollateral(
        uint8 ilkIndex,
        uint256 depositAmount,
        uint256 leverageAmount,
        bool depositIsWeth
    )
        external
    {
        IERC20 ilkAddress = IERC20(ionPool.getIlkAddress(ilkIndex));

        uint256 leverageAmountInCollateralUnits = _getLstAmountOut(ilkIndex, leverageAmount);
        if (ilkAddress.balanceOf(address(vault)) < leverageAmountInCollateralUnits) {
            revert InsufficientLiquidityForFlashloan();
        }

        IERC20[] memory addresses = new IERC20[](1);
        addresses[0] = ilkAddress;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = leverageAmountInCollateralUnits;

        flashLoanInitiated = 2;

        vault.flashLoan(
            IFlashLoanRecipient(address(this)),
            addresses,
            amounts,
            abi.encode(ilkIndex, msg.sender, depositAmount, leverageAmount, depositIsWeth)
        );

        flashLoanInitiated = 1;
    }

    /**
     * @notice Code assumes Balancer flashloans remain free
     * @param ilkIndex of the collateral
     * @param depositAmount in WETH terms
     * @param leverageAmount in WETH terms
     */
    function flashLeverageWeth(
        uint8 ilkIndex,
        uint256 depositAmount,
        uint256 leverageAmount,
        bool depositIsWeth
    )
        external
        payable
    {
        if (weth.balanceOf(address(vault)) < leverageAmount) revert InsufficientLiquidityForFlashloan();

        IERC20[] memory addresses = new IERC20[](1);
        addresses[0] = IERC20(address(weth));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = leverageAmount;

        flashLoanInitiated = 2;

        vault.flashLoan(
            IFlashLoanRecipient(address(this)),
            addresses,
            amounts,
            abi.encode(ilkIndex, msg.sender, depositAmount, leverageAmount, depositIsWeth)
        );

        flashLoanInitiated = 1;
    }

    /**
     * @notice Code assumes Balancer flashloans remain free
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
        // The deposit amount is in WETH terms
        (uint8 ilkIndex, address user, uint256 depositAmount, uint256 leverageAmount, bool depositIsWeth) =
            abi.decode(userData, (uint8, address, uint256, uint256, bool));

        // Flashloaned WETH needs to be wrapped into collateral asset
        if (address(token) == address(weth)) {
            // Sanity check
            assert(leverageAmount == amounts[0]);

            // WETH will be transferred from the user and wrapped into collateral asset
            if (depositIsWeth) {
                weth.transferFrom(user, address(this), depositAmount);
                // (leverageAmount + depositAmount) WETH

                _depositWethForLst(ilkIndex, leverageAmount + depositAmount);
                // (leverageAmount + depositAmount) collateral token
            }
            // Collateral asset will be transferred from the user
            else {
                IERC20 ilkAddress = IERC20(ionPool.getIlkAddress(ilkIndex));
                ilkAddress.transferFrom(user, address(this), _getLstAmountOut(ilkIndex, depositAmount));
                // (leverageAmount) WETH + (depositAmount) collateral token

                _depositWethForLst(ilkIndex, leverageAmount);
                // (leverageAmount + depositAmount) collateral token
            }

            _depositAndBorrow(
                ilkIndex, user, address(this), _getLstAmountOut(ilkIndex, depositAmount + leverageAmount), leverageAmount
            );
            // leverageAmount of WETH with (depositAmount + leverageAmount) of collateral token inside vault

            weth.transfer(address(vault), leverageAmount);
            // 0 WETH
        } else {
            if (ionPool.getIlkAddress(ilkIndex) != address(token)) revert FlashLoanedInvalidToken();

            if (depositIsWeth) {
                weth.transferFrom(user, address(this), depositAmount);
                // (depositAmount) WETH + (leverageAmount) collateral token

                _depositWethForLst(ilkIndex, depositAmount);
                // (leverageAmount + depositAmount) collateral token
            } else {
                IERC20 ilkAddress = IERC20(ionPool.getIlkAddress(ilkIndex));
                ilkAddress.transferFrom(user, address(this), _getLstAmountOut(ilkIndex, depositAmount));
                // (depositAmount + leverageAmount) collateral token
            }

            _depositAndBorrow(
                ilkIndex, user, address(this), _getLstAmountOut(ilkIndex, depositAmount + leverageAmount), leverageAmount
            );

            weth.transfer(address(vault), depositAmount);
        }

        flashLoanInitiated = 1;
    }

    function depositAndBorrow(uint8 ilkIndex, uint256 amountCollateral, uint256 amountToBorrow) external {
        IERC20 ilkAddress = IERC20(ionPool.getIlkAddress(ilkIndex));
        ilkAddress.transferFrom(msg.sender, address(this), amountCollateral);
        _depositAndBorrow(ilkIndex, msg.sender, msg.sender, amountCollateral, amountToBorrow);
    }

    /**
     * 
     * @param ilkIndex of the collateral
     * @param vaultHolder the user who will be responsible for repaying debt
     * @param receiver the user who receives the borrowed funds
     * @param amountCollateral to move into vault
     * @param amountToBorrow out of the vault
     */
    function _depositAndBorrow(
        uint8 ilkIndex,
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

        ionPool.borrow(ilkIndex, vaultHolder, receiver, amountToBorrow);
    }

    function _depositWethForLst(uint8 ilkIndex, uint256 amount) internal {
        weth.withdraw(amount);
        address payable depositContract = payable(ionRegistry.depositContracts(ilkIndex));

        if (ilkIndex == 0) {
            (bool success,) = depositContract.call{ value: amount }("");
            if (!success) revert WstEthDepositFailed();
        } else if (ilkIndex == 1) {
            IStaderDeposit(depositContract).deposit{ value: amount }(address(this));
        } else if (ilkIndex == 2) {
            ISwellDeposit(depositContract).deposit{ value: amount }();
        } else {
            revert("Invalid ilkIndex");
        }
    }

    function _getLstAmountOut(uint8 ilkIndex, uint256 amountWeth) internal view returns (uint256) {
        address depositContract = ionRegistry.depositContracts(ilkIndex);

        if (ilkIndex == 0) {
            return ILidoWStEthDeposit(depositContract).getWstETHByStETH(amountWeth);
        } else if (ilkIndex == 1) {
            return IStaderDeposit(depositContract).previewDeposit(amountWeth);
        } else if (ilkIndex == 2) {
            return ISwellDeposit(depositContract).ethToSwETHRate() * amountWeth;
        } else {
            revert("Invalid ilkIndex");
        }
    }

    receive() external payable {
        if (msg.sender != address(weth)) revert CannotSendEthToContract();
    }
}
