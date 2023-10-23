// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../IonPool.sol";
import { IonRegistry } from "./../../IonRegistry.sol";
import { IWETH9 } from "../../../interfaces/IWETH9.sol";
import { GemJoin } from "../../../join/GemJoin.sol";
import { RoundedMath } from "../../../libraries/math/RoundedMath.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
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
abstract contract IonHandlerBase {
    using SafeERC20 for IERC20;
    using RoundedMath for uint256;

    error CannotSendEthToContract();

    enum AmountToBorrow {
        IS_MIN,
        IS_MAX
    }

    IWETH9 immutable weth;
    uint8 immutable ilkIndex;
    IonPool immutable ionPool;
    // TODO: Instead of passing registry, just pass GemJoin directly
    GemJoin immutable gemJoin;
    IERC20 immutable lstToken;

    constructor(uint8 _ilkIndex, IonPool _ionPool, IonRegistry _ionRegistry) {
        ionPool = _ionPool;
        ilkIndex = _ilkIndex;

        IWETH9 _weth = IWETH9(address(ionPool.underlying()));
        weth = _weth;

        address ilkAddress = ionPool.getIlkAddress(_ilkIndex);
        lstToken = IERC20(ilkAddress);

        GemJoin _gemJoin = _ionRegistry.gemJoins(_ilkIndex);
        gemJoin = _gemJoin;

        _weth.approve(address(ionPool), type(uint256).max);
        IERC20(ilkAddress).approve(address(_gemJoin), type(uint256).max);
    }

    function depositAndBorrow(uint256 amountCollateral, uint256 amountToBorrow) external {
        lstToken.safeTransferFrom(msg.sender, address(this), amountCollateral);
        _depositAndBorrow(msg.sender, msg.sender, amountCollateral, amountToBorrow, AmountToBorrow.IS_MAX);
    }

    /**
     *
     * @param vaultHolder the user who will be responsible for repaying debt
     * @param receiver the user who receives the borrowed funds
     * @param amountCollateral to move into vault
     * @param amountToBorrow out of the vault [WAD]
     * @param amountToBorrowType whether the `amountToBorrow` is a min or max.
     * This will dictate the rounding direction when converting to normalized
     * amount. If it is a minimum, then the rounding will be rounded up. If it
     * is a maximum, then the rounding will be rounded down.
     */
    function _depositAndBorrow(
        address vaultHolder,
        address receiver,
        uint256 amountCollateral,
        uint256 amountToBorrow,
        AmountToBorrow amountToBorrowType
    )
        internal
    {
        gemJoin.join(address(this), amountCollateral);

        ionPool.moveGemToVault(ilkIndex, vaultHolder, address(this), amountCollateral);

        uint256 currentRate = ionPool.rate(ilkIndex);

        uint256 normalizedAmountToBorrow;
        if (amountToBorrowType == AmountToBorrow.IS_MIN) {
            normalizedAmountToBorrow = amountToBorrow.rayDivUp(currentRate);
        } else {
            normalizedAmountToBorrow = amountToBorrow.rayDivDown(currentRate);
        }

        if (amountToBorrow != 0) ionPool.borrow(ilkIndex, vaultHolder, receiver, normalizedAmountToBorrow);
    }

    function repayAndWithdraw(uint256 collateralToWithdraw, uint256 debtToRepay) external {
        weth.transferFrom(msg.sender, address(this), debtToRepay);
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
        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 normalizedDebtToRepay = debtToRepay.rayDivDown(currentRate);

        ionPool.repay(ilkIndex, vaultHolder, address(this), normalizedDebtToRepay);

        ionPool.moveGemFromVault(ilkIndex, vaultHolder, address(this), collateralToWithdraw);

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
