// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../../../IonPool.sol";
import { IWETH9 } from "../../../interfaces/IWETH9.sol";
import { GemJoin } from "../../../join/GemJoin.sol";
import { WadRayMath, RAY } from "../../../libraries/math/WadRayMath.sol";
import { Whitelist } from "../../../Whitelist.sol";
import { WETH_ADDRESS } from "../../../Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice The base handler contract for simpler interactions with the `IonPool`
 * core contract. It combines various individual interactions into one compound
 * interaction to facilitate reaching user end-goals in atomic fashion.
 *
 * @dev To actually borrow from `IonPool`, a user must submit a "normalized" borrow
 * amount. This contract is designed to be user-intuitive and, thus, allows a user
 * to submit a standard desired borrow amount, which this contract will then
 * convert into to the appropriate "normalized" borrow amount.
 *
 * @custom:security-contact security@molecularlabs.io
 */
abstract contract IonHandlerBase {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH9;
    using WadRayMath for uint256;

    error CannotSendEthToContract();
    error FlashloanRepaymentTooExpensive(uint256 repaymentAmount, uint256 maxRepaymentAmount);
    error TransactionDeadlineReached(uint256 deadline);

    /**
     * @notice Checks if the tx is being executed before the designated deadline
     * for execution.
     * @dev This is used to prevent txs that have sat in the mempool for too
     * long from executing at unintended prices.
     */
    modifier checkDeadline(uint256 deadline) {
        if (deadline <= block.timestamp) revert TransactionDeadlineReached(deadline);
        _;
    }

    /**
     * @notice Checks if `msg.sender` is on the whitelist.
     * @dev This contract will be on the `protocolControlledWhitelist`. As such,
     * it will validate that users are on the whitelist itself and be able to
     * bypass the whitelist check on `IonPool`.
     * @param proof to validate the whitelist check.
     */
    modifier onlyWhitelistedBorrowers(bytes32[] memory proof) {
        WHITELIST.isWhitelistedBorrower(ILK_INDEX, msg.sender, msg.sender, proof);
        _;
    }

    /**
     * @dev During conversion from borrow amount -> "normalized" borrow amount,"
     * there is division required. In certain scenarios, it may be desirable to
     * round up during division, in others, to round down. This enum allows a
     * developer to indicate the rounding direction by describing the
     * `amountToBorrow`. If it `IS_MIN`, then the final borrowed amount should
     * be larger than `amountToBorrow` (round up), and vice versa for `IS_MAX`
     * (round down).
     */
    enum AmountToBorrow {
        IS_MIN,
        IS_MAX
    }

    IERC20 public immutable BASE;
    // Will keep WETH for compatability with other strategies. But this should
    // be removed eventually to remove dependence on WETH as a base asset.
    IWETH9 public immutable WETH;
    uint8 public immutable ILK_INDEX;
    IonPool public immutable POOL;
    GemJoin public immutable JOIN;
    IERC20 public immutable LST_TOKEN;
    Whitelist public immutable WHITELIST;

    /**
     * @notice Creates a new instance of `IonHandlerBase`
     * @param _ilkIndex of the ilk for which this instance is associated with.
     * @param _ionPool address of `IonPool` core contract.
     * @param _gemJoin the `GemJoin` associated with the `ilkIndex` of this
     * contract.
     * @param _whitelist the `Whitelist` module address.
     */
    constructor(uint8 _ilkIndex, IonPool _ionPool, GemJoin _gemJoin, Whitelist _whitelist) {
        POOL = _ionPool;
        ILK_INDEX = _ilkIndex;

        BASE = IERC20(_ionPool.underlying());

        IWETH9 _weth = WETH_ADDRESS;
        WETH = _weth;

        address ilkAddress = POOL.getIlkAddress(_ilkIndex);
        LST_TOKEN = IERC20(ilkAddress);

        JOIN = _gemJoin;

        WHITELIST = _whitelist;

        BASE.approve(address(_ionPool), type(uint256).max);
        IERC20(ilkAddress).approve(address(_gemJoin), type(uint256).max);
    }

    /**
     * @notice Combines gem-joining and depositing collateral and then borrowing
     * into one compound action.
     * @param amountCollateral Amount of collateral to deposit. [WAD]
     * @param amountToBorrow Amount of WETH to borrow. Due to rounding, true
     * borrow amount might be slightly less. [WAD]
     * @param proof that the user is whitelisted.
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
     * @notice Handles all logic to gem-join and deposit collateral, followed by
     * a borrow. It is also possible to use this function simply to gem-join and
     * deposit collateral atomically by setting `amountToBorrow` to 0.
     * @param vaultHolder The user who will be responsible for repaying debt.
     * @param receiver The user who receives the borrowed funds.
     * @param amountCollateral to move into vault. [WAD]
     * @param amountToBorrow out of the vault. [WAD]
     * @param amountToBorrowType Whether the `amountToBorrow` is a min or max.
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

        uint256 rate = POOL.rate(ILK_INDEX);

        uint256 normalizedAmountToBorrow;
        if (amountToBorrowType == AmountToBorrow.IS_MIN) {
            normalizedAmountToBorrow = amountToBorrow.rayDivUp(rate);
        } else {
            normalizedAmountToBorrow = amountToBorrow.rayDivDown(rate);
        }

        POOL.borrow(ILK_INDEX, vaultHolder, receiver, normalizedAmountToBorrow, new bytes32[](0));
    }

    /**
     * @notice Will repay all debt and withdraw desired collateral amount. This
     * function can also simply be used for a full repayment (which may be
     * difficult through a direct tx to the `IonPool`) by setting
     * `collateralToWithdraw` to 0.
     * @dev Will repay the debt belonging to `msg.sender`. This function is
     * necessary because with `rate` updating every single block, it may be
     * difficult to repay a full amount if a user uses the total debt from a
     * previous block. If a user ends up repaying all but dust amounts of debt
     * (due to a slight `rate` change), then they repayment will likely fail due
     * to the `dust` parameter.
     * @param collateralToWithdraw in collateral terms. [WAD]
     */
    function repayFullAndWithdraw(uint256 collateralToWithdraw) external {
        (uint256 repayAmount, uint256 normalizedDebtToRepay) = _getFullRepayAmount(msg.sender);

        BASE.safeTransferFrom(msg.sender, address(this), repayAmount);

        POOL.repay(ILK_INDEX, msg.sender, address(this), normalizedDebtToRepay);

        POOL.withdrawCollateral(ILK_INDEX, msg.sender, address(this), collateralToWithdraw);

        JOIN.exit(msg.sender, collateralToWithdraw);
    }

    /**
     * @notice Helper function to get the repayment amount for all the debt of a
     * `user`.
     * @dev This simply emulates the rounding behaviour of the `IonPool` to
     * arrive at an accurate value.
     * @param user Address of the user.
     * @return repayAmount Amount of base asset required to repay all debt (this
     * mimics IonPool's behavior). [WAD]
     * @return normalizedDebt Total normalized debt held by `user`'s vault.
     * [WAD]
     */
    function _getFullRepayAmount(address user) internal view returns (uint256 repayAmount, uint256 normalizedDebt) {
        uint256 currentRate = POOL.rate(ILK_INDEX);

        normalizedDebt = POOL.normalizedDebt(ILK_INDEX, user);

        // This is exactly how IonPool calculates the amount of base asset
        // required
        uint256 amountRad = normalizedDebt * currentRate;
        repayAmount = amountRad / RAY;
        if (amountRad % RAY > 0) ++repayAmount;
    }

    /**
     * @notice Combines repaying debt and then withdrawing and gem-exitting
     * collateral into one compound action.
     *
     * If repaying **all** is the intention, use `repayFullAndWithdraw()`
     * instead to prevent tx revert from dust amounts of debt in vault.
     * @param debtToRepay In ETH terms. [WAD]
     * @param collateralToWithdraw In collateral terms. [WAD]
     */
    function repayAndWithdraw(uint256 debtToRepay, uint256 collateralToWithdraw) external {
        BASE.safeTransferFrom(msg.sender, address(this), debtToRepay);
        _repayAndWithdraw(msg.sender, msg.sender, collateralToWithdraw, debtToRepay);
    }

    /**
     * @notice Handles all logic to repay debt, followed by a collateral
     * withdrawal and gem-exit. This function can also be used to just withdraw
     * and gem-exit in atomic fashion by setting the `debtToRepay` to 0.
     * @param vaultHolder The user whose debt will be repaid.
     * @param receiver The user who receives the the withdrawn collateral.
     * @param collateralToWithdraw to move into vault. [WAD]
     * @param debtToRepay out of the vault. [WAD]
     */
    function _repayAndWithdraw(
        address vaultHolder,
        address receiver,
        uint256 collateralToWithdraw,
        uint256 debtToRepay
    )
        internal
    {
        uint256 currentRate = POOL.rate(ILK_INDEX);

        uint256 normalizedDebtToRepay = debtToRepay.rayDivDown(currentRate);

        POOL.repay(ILK_INDEX, vaultHolder, address(this), normalizedDebtToRepay);

        POOL.withdrawCollateral(ILK_INDEX, vaultHolder, address(this), collateralToWithdraw);

        JOIN.exit(receiver, collateralToWithdraw);
    }

    /**
     * @notice ETH cannot be directly sent to this contract.
     * @dev To allow unwrapping of WETH into ETH.
     */
    receive() external payable {
        if (msg.sender != address(WETH_ADDRESS)) revert CannotSendEthToContract();
    }
}
