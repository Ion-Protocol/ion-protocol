pragma solidity ^0.8.19;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { RoundedMath, WAD, RAY } from "../src/libraries/math/RoundedMath.sol";
import { IonPool } from "src//IonPool.sol";
import "forge-std/console.sol";

// TODO: import instead when ReserveOracle is finished
interface IReserveOracle {
    function getExchangeRate(uint256 ilkIndex) external view returns (uint256 exchangeRate);
}

// DEPLOY PARAMETERS
// NOTE: Needs to be configured on each deployment along with constructor parameters
// TODO: Can this be inside the constructor?
uint32 constant ILK_COUNT = 8;
uint256 constant TARGET_HEALTH = 125 * WAD / 100; // 1.25 [wad]
uint256 constant RESERVE_FACTOR = 2 * WAD / 100; // 0.02 [wad]
uint256 constant MAX_DISCOUNT = 2 * WAD / 10; // 0.20 [wad]

contract Liquidation {
    using SafeERC20 for IERC20;
    using RoundedMath for uint256;

    error LiquidationThresholdCannotBeZero(uint256 liquidationThreshold);
    error ExchangeRateCannotBeZero(uint256 exchangeRate);
    error VaultIsNotUnsafe(uint256 healthRatio);

    // --- parameters ---

    // ilk specific variable
    uint64[ILK_COUNT] public liquidationThresholds; // [wad] indexed by ilkIndex

    address public immutable revenueRecipient;

    IonPool public immutable ionPool;
    IReserveOracle public immutable reserveOracle;
    IERC20 public immutable underlying;

    struct LiquidateArgs {
        uint256 repay;
        uint256 gemOut;
        uint256 dart;
        uint256 fee;
    }

    // --- Events ---
    event Liquidate(address kpr, uint256 indexed repay, uint256 indexed gemOutLessFee, uint256 fee);

    constructor(
        address _ionPool,
        address _reserveOracle,
        address _revenueRecipient,
        uint64[ILK_COUNT] memory _liquidationThresholds
    ) {
        ionPool = IonPool(_ionPool);
        reserveOracle = IReserveOracle(_reserveOracle);
        revenueRecipient = _revenueRecipient;
        liquidationThresholds = _liquidationThresholds;
        underlying = ionPool.underlying();
    }

    /**
     * @dev internal helper function for liquidation math. Final repay amount
     * NOTE: find better way to handle precision
     * @param totalDebt [rad] this needs to be rad since repay can be set to totalDebt
     * @param dust [rad]
     * @param collateral [wad]
     * @param exchangeRate [wad]
     * @param liquidationThreshold [wad]
     * @param discount [wad]
     * @return repay [rad]
     * @return gemOut [wad]
     */
    function _getRepayAmt(
        uint256 totalDebt,
        uint256 dust,
        uint256 collateral,
        uint256 exchangeRate,
        uint256 liquidationThreshold,
        uint256 discount
    )
        internal
        view
        returns (uint256 repay, uint256 gemOut)
    {
        // repayNum = (targetHealth * totalDebt - collateral * exchangeRate * liquidationThreshold)
        // [wad] * _scaleToRay([wad]) -  [wad] * [wad] * [wad]
        // repayDen = (targetHealth - (liquidationThreshold / (1 - discount)))
        // [wad] - ([wad] / (1 - [wad]))
        uint256 repayNum = TARGET_HEALTH.roundedWadMul(totalDebt.scaleToRay(45))
            - collateral.roundedWadMul(exchangeRate).roundedWadMul(liquidationThreshold); // [wad]
        uint256 repayDen = TARGET_HEALTH - liquidationThreshold.roundedWadDiv((WAD - discount)); // [wad]
        repay = repayNum.roundedWadDiv(repayDen).scaleToRad(18); // [rad]

        // first branch: full liquidation
        //   more debt needs to be paid off than available to go back to target health,
        //   so all collateral is sold off and the alleth repay amount is readjusted
        // second branch: resulting debt below dust
        //   there is enough collateral to cover the debt and go back to target health,
        //   but it would leave a debt amount less than dust. So just pay off all dust
        //   and readjust the collateral
        // third branch: soft liquidation to target health ratio
        if (repay > totalDebt) {
            gemOut = collateral; // [wad] sell all collateral
            repay = exchangeRate.roundedWadMul(WAD - discount).roundedWadMul(gemOut).scaleToRad(18); // [rad] readjust
                // repay amount
        } else if (totalDebt - repay < dust) {
            repay = totalDebt; // [rad] pay off all debt
            gemOut = repay.scaleToWad(45).roundedWadDiv(exchangeRate.roundedWadMul(WAD - discount)); // [wad] readjust
                // collateral to sell
        } else {
            // repay stays same
            gemOut = repay.scaleToWad(45).roundedWadDiv(exchangeRate.roundedWadMul(WAD - discount)); // [wad] readjust
                // collateral to sell
        }
    }

    /**
     * @dev Executes collateral sale and repayment of debt by liquidators.
     * NOTE: assumes that the kpr already has internal alleth
     *       and approved liq to move its alleth.
     */
    function liquidate(
        uint8 ilkIndex,
        address vault, // urn to be liquidated
        address kpr // receiver of collateral
    )
        external
    {
        // --- Calculations ---

        LiquidateArgs memory liquidateArgs;

        // needs ink art rate
        // TODO: multiple external calls vs. calling one getter that returns all
        uint256 collateral = ionPool.collateral(ilkIndex, vault);
        uint256 normalizedDebt = ionPool.normalizedDebt(ilkIndex, vault);
        uint256 rate = ionPool.rate(ilkIndex);
        uint256 dust = ionPool.dust(ilkIndex);

        console.log("liqThres 0: ", liquidationThresholds[0]);
        console.log("liqThres 1: ", liquidationThresholds[1]);
        console.log("liqThres 2: ", liquidationThresholds[2]);
        uint256 liquidationThreshold = liquidationThresholds[ilkIndex]; // []
        uint256 exchangeRate = reserveOracle.getExchangeRate(ilkIndex); // [ray]

        if (exchangeRate == 0) {
            revert ExchangeRateCannotBeZero(exchangeRate);
        }
        if (liquidationThreshold == 0) {
            revert LiquidationThresholdCannotBeZero(liquidationThreshold);
        }

        /**
         * health score = (ink * spot) * mat) / (art * rate)
         * [wad] * [ray] * [ray] / ([wad] * [ray]) = [ray]
         */

        // healthScore = collateral * exchangeRate * liquidationThreshold / (normalized Debt * rate)
        //             = [wad] * [wad] * [wad] / ([wad] * [ray])
        // the rate gets scaled to [wad] and the healthScore output should be in [wad]
        console.log("collateral: ", collateral);
        console.log("exchangeRate: ", exchangeRate);
        console.log("liquidationThreshold: ", liquidationThreshold);
        console.log("collateral * exchangeRate: ", collateral.roundedWadMul(exchangeRate));
        console.log(
            "collateral * exchangeRate * liquidationThreshold: ",
            collateral.roundedWadMul(exchangeRate).roundedWadMul(liquidationThreshold)
        );
        uint256 healthRatio = collateral.roundedWadMul(exchangeRate).roundedWadMul(liquidationThreshold); // [wad] *
            // [wad] * [wad] = [wad]
        healthRatio = healthRatio.roundedWadDiv(normalizedDebt).roundedWadDiv(rate.scaleToWad(27)); // [wad] / [wad] /
            // [wad] = [wad]

        if (healthRatio >= WAD) {
            revert VaultIsNotUnsafe(healthRatio);
        }

        uint256 discount = RESERVE_FACTOR + (WAD - healthRatio); // [ray] + ([ray] - [ray])
        discount = discount <= MAX_DISCOUNT ? discount : MAX_DISCOUNT; // cap discount to maxDiscount

        (liquidateArgs.repay, liquidateArgs.gemOut) =
            _getRepayAmt(discount, normalizedDebt * rate, collateral, exchangeRate, liquidationThreshold, dust);

        liquidateArgs.dart = liquidateArgs.gemOut >= collateral ? normalizedDebt : liquidateArgs.repay / rate; // normalize
            // the repay amount by rate to get the actual dart to frob

        liquidateArgs.fee = liquidateArgs.gemOut * RESERVE_FACTOR / RAY; // [wad] * [ray] / [ray] = [wad]

        // --- Storage Updates ---

        // move weth from kpr to liq
        underlying.safeTransferFrom(kpr, address(this), liquidateArgs.repay);

        // confiscate part of the urn
        //  1. move art into liq's sin (unbacked debt)
        //  2. move ink into liq's gem (unlocked collateral)
        //  NOTE: if all collateral is sold (gemOut == ink), then (dart = art)
        //        this confiscates all debt. What doesn't get paid off by liquidation gets passed to the vow.
        //        if not all collateral is sold (gemOut < ink), confiscate only the debt to be paid off

        require(int256(liquidateArgs.gemOut) >= 0 && int256(liquidateArgs.dart) >= 0, "Liq/dart-overflow");

        // moves the art into liq's sin and ink into liq's gem
        ionPool.confiscateVault(
            ilkIndex, vault, address(this), address(this), -int256(liquidateArgs.gemOut), -int256(liquidateArgs.dart)
        );

        // give the unlocked collateral minus the fee to the kpr
        ionPool.transferGem(ilkIndex, address(this), kpr, liquidateArgs.gemOut - liquidateArgs.fee);

        // reserve fee: give the fee in collateral to the revenueRecipient
        ionPool.transferGem(ilkIndex, address(this), revenueRecipient, liquidateArgs.fee);

        // payback liquidation's unbacked debt with the underlying ERC20
        // if all collateral was sold and debt remains, this contract keeps the sin
        ionPool.repayBadDebt(liquidateArgs.repay);

        emit Liquidate(kpr, liquidateArgs.repay, liquidateArgs.gemOut - liquidateArgs.fee, liquidateArgs.fee);
    }
}
