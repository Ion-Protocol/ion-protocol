// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../IonPool.sol";
import { IWETH9 } from "../../../interfaces/IWETH9.sol";
import { GemJoin } from "../../../join/GemJoin.sol";
import { WadRayMath, RAY } from "../../../libraries/math/WadRayMath.sol";
import { Whitelist } from "../../../Whitelist.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
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
abstract contract IonHandlerBase {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH9;
    using WadRayMath for uint256;

    error CannotSendEthToContract();
    error FlashloanRepaymentTooExpensive(uint256 repaymentAmount, uint256 maxRepaymentAmount);
    error TransactionDeadlineReached(uint256 deadline);

    modifier checkDeadline(uint256 deadline) {
        if (deadline <= block.timestamp) revert TransactionDeadlineReached(deadline);
        _;
    }

    enum AmountToBorrow {
        IS_MIN,
        IS_MAX
    }

    IWETH9 public immutable WETH;
    uint8 public immutable ILK_INDEX;
    IonPool public immutable POOL;
    GemJoin public immutable JOIN;
    IERC20 public immutable LST_TOKEN;
    Whitelist public immutable WHITELIST;

    modifier onlyWhitelistedBorrowers(bytes32[] memory proof) {
        WHITELIST.isWhitelistedBorrower(ILK_INDEX, msg.sender, msg.sender, proof);
        _;
    }

    constructor(uint8 _ilkIndex, IonPool _ionPool, GemJoin _gemJoin, Whitelist _whitelist) {
        POOL = _ionPool;
        ILK_INDEX = _ilkIndex;

        IWETH9 _weth = IWETH9(address(_ionPool.underlying()));
        WETH = _weth;

        address ilkAddress = POOL.getIlkAddress(_ilkIndex);
        LST_TOKEN = IERC20(ilkAddress);

        JOIN = _gemJoin;

        WHITELIST = _whitelist;

        _weth.approve(address(_ionPool), type(uint256).max);
        IERC20(ilkAddress).approve(address(_gemJoin), type(uint256).max);
    }

    /**
     *
     * @param amountCollateral amount of collateral to deposit.
     * @param amountToBorrow amount of WETH to borrow. Due to rounding, true borrow amount might be slightly less.
     * @param proof merkle proof that the user is whitelisted.
     */
    function depositAndBorrow(
        uint256 amountCollateral,
        uint256 amountToBorrow,
        bytes32[] calldata proof
    )
        external
        onlyWhitelistedBorrowers(proof)
    {
        LST_TOKEN.safeTransferFrom(msg.sender, address(this), amountCollateral);
        _depositAndBorrow(msg.sender, msg.sender, amountCollateral, amountToBorrow, AmountToBorrow.IS_MAX);
    }

    /**
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
        JOIN.join(address(this), amountCollateral);

        POOL.depositCollateral(ILK_INDEX, vaultHolder, address(this), amountCollateral, new bytes32[](0));

        if (amountToBorrow == 0) return;

        uint256 currentRate = POOL.rate(ILK_INDEX);
        (,, uint256 newRateIncrease,,) = POOL.calculateRewardAndDebtDistribution(ILK_INDEX);
        uint256 rateAfterAccrual = currentRate + newRateIncrease;

        uint256 normalizedAmountToBorrow;
        if (amountToBorrowType == AmountToBorrow.IS_MIN) {
            normalizedAmountToBorrow = amountToBorrow.rayDivUp(rateAfterAccrual);
        } else {
            normalizedAmountToBorrow = amountToBorrow.rayDivDown(rateAfterAccrual);
        }

        POOL.borrow(ILK_INDEX, vaultHolder, receiver, normalizedAmountToBorrow, new bytes32[](0));
    }

    /**
     * @notice Will repay all debt and withdraw desired collateral amount
     * @dev Will repay the debt belonging to `msg.sender`
     * @param collateralToWithdraw in collateral terms
     */
    function repayFullAndWithdraw(uint256 collateralToWithdraw) external {
        (uint256 repayAmount, uint256 normalizedDebtToRepay) = _getFullRepayAmount(msg.sender);

        WETH.safeTransferFrom(msg.sender, address(this), repayAmount);

        POOL.repay(ILK_INDEX, msg.sender, address(this), normalizedDebtToRepay);

        POOL.withdrawCollateral(ILK_INDEX, msg.sender, address(this), collateralToWithdraw);

        JOIN.exit(msg.sender, collateralToWithdraw);
    }

    /**
     * @dev Helper function to get the repayment amount for all the debt of a `user`.
     * @param user address of the user
     * @return repayAmount amount of WETH required to repay all debt (this mimics IonPool's behavior)
     * @return normalizedDebt total normalized debt held by user's vault
     */
    function _getFullRepayAmount(address user) internal view returns (uint256 repayAmount, uint256 normalizedDebt) {
        uint256 currentRate = POOL.rate(ILK_INDEX);
        (,, uint256 newRateIncrease,,) = POOL.calculateRewardAndDebtDistribution(ILK_INDEX);
        uint256 rateAfterAccrual = currentRate + newRateIncrease;

        normalizedDebt = POOL.normalizedDebt(ILK_INDEX, user);

        // This is exactly how IonPool calculates the amount of weth required
        uint256 amountRad = normalizedDebt * rateAfterAccrual;
        repayAmount = amountRad / RAY;
        if (amountRad % RAY > 0) ++repayAmount;
    }

    /**
     * @param debtToRepay in eth terms
     * @param collateralToWithdraw in collateral terms
     */
    function repayAndWithdraw(uint256 debtToRepay, uint256 collateralToWithdraw) external {
        WETH.safeTransferFrom(msg.sender, address(this), debtToRepay);
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
        uint256 currentRate = POOL.rate(ILK_INDEX);
        (,, uint256 newRateIncrease,,) = POOL.calculateRewardAndDebtDistribution(ILK_INDEX);
        uint256 rateAfterAccrual = currentRate + newRateIncrease;

        uint256 normalizedDebtToRepay = debtToRepay.rayDivDown(rateAfterAccrual);

        POOL.repay(ILK_INDEX, vaultHolder, address(this), normalizedDebtToRepay);

        POOL.withdrawCollateral(ILK_INDEX, vaultHolder, address(this), collateralToWithdraw);

        JOIN.exit(receiver, collateralToWithdraw);
    }

    /**
     * @dev To allow unwrapping of WETH into ETH
     */
    receive() external payable {
        if (msg.sender != address(WETH)) revert CannotSendEthToContract();
    }
}
