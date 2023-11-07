// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { WadRayMath, WAD, RAY } from "./libraries/math/WadRayMath.sol";
import { IonPool } from "src/IonPool.sol";
import { ReserveOracle } from "src/oracles/reserve/ReserveOracle.sol";
import "forge-std/console.sol";

uint8 constant ILK_COUNT = 8;

contract Liquidation {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;

    error LiquidationThresholdCannotBeZero(uint256 liquidationThreshold);
    error ExchangeRateCannotBeZero(uint256 exchangeRate);
    error VaultIsNotUnsafe(uint256 healthRatio);

    // --- parameters ---

    uint256 immutable TARGET_HEALTH; // [ray]
    uint256 immutable RESERVE_FACTOR; // [ray]
    uint256 immutable MAX_DISCOUNT; // [ray]

    // liquidation thresholds
    uint256 public immutable LIQUIDATION_THRESHOLD_0;
    uint256 public immutable LIQUIDATION_THRESHOLD_1;
    uint256 public immutable LIQUIDATION_THRESHOLD_2;

    // exchange rates
    address public immutable EXCHANGE_RATE_ORACLE_0;
    address public immutable EXCHANGE_RATE_ORACLE_1;
    address public immutable EXCHANGE_RATE_ORACLE_2;

    address public immutable REVENUE_RECIPIENT; // receives fees
    address public immutable PROTOCOL; // receives confiscated vault debt and collateral

    IonPool public immutable ionPool;
    IERC20 public immutable underlying;

    // --- Events ---
    event Liquidate(address kpr, uint256 indexed repay, uint256 indexed gemOutLessFee, uint256 fee);

    constructor(
        address _ionPool,
        address _revenueRecipient,
        address _protocol,
        address[] memory _exchangeRateOracles,
        uint256[ILK_COUNT] memory _liquidationThresholds,
        uint256 _targetHealth,
        uint256 _reserveFactor,
        uint256 _maxDiscount
    ) {
        ionPool = IonPool(_ionPool);
        REVENUE_RECIPIENT = _revenueRecipient;
        PROTOCOL = _protocol;

        TARGET_HEALTH = _targetHealth;
        RESERVE_FACTOR = _reserveFactor;
        MAX_DISCOUNT = _maxDiscount;

        underlying = ionPool.underlying();
        underlying.approve(address(ionPool), type(uint256).max); // approve ionPool to transfer the underlying asset

        LIQUIDATION_THRESHOLD_0 = _liquidationThresholds[0];
        LIQUIDATION_THRESHOLD_1 = _liquidationThresholds[1];
        LIQUIDATION_THRESHOLD_2 = _liquidationThresholds[2];

        EXCHANGE_RATE_ORACLE_0 = _exchangeRateOracles[0];
        EXCHANGE_RATE_ORACLE_1 = _exchangeRateOracles[1];
        EXCHANGE_RATE_ORACLE_2 = _exchangeRateOracles[2];
    }

    function _getExchangeRateAndLiquidationThreshold(uint8 ilkIndex)
        internal
        view
        returns (uint256 liquidationThreshold, uint256 exchangeRate)
    {
        address exchangeRateOracle;
        if (ilkIndex == 0) {
            exchangeRateOracle = EXCHANGE_RATE_ORACLE_0;
            liquidationThreshold = LIQUIDATION_THRESHOLD_0;
        } else if (ilkIndex == 1) {
            exchangeRateOracle = EXCHANGE_RATE_ORACLE_1;
            liquidationThreshold = LIQUIDATION_THRESHOLD_1;
        } else if (ilkIndex == 2) {
            exchangeRateOracle = EXCHANGE_RATE_ORACLE_2;
            liquidationThreshold = LIQUIDATION_THRESHOLD_2;
        }
        // exchangeRate is reported in uint72 in [wad], but should be converted to uint256 [ray]
        exchangeRate = ReserveOracle(exchangeRateOracle).currentExchangeRate();
        exchangeRate = uint256(exchangeRate).scaleUpToRay(18);
    }

    /**
     * @dev internal helper function for liquidation math. Final repay amount
     * NOTE: find better way to handle precision
     * @param debtValue [rad] this needs to be rad since repay can be set to totalDebt
     * @param collateralValue [rad]
     * @param liquidationThreshold [ray]
     * @param discount [ray]
     * @return repay [rad]
     */
    // TODO: just get rid of this helper function
    function _getRepayAmt(
        uint256 debtValue,
        uint256 collateralValue,
        uint256 liquidationThreshold,
        uint256 discount
    )
        internal
        view
        returns (uint256 repay)
    {
        // repayNum = (targetHealth * totalDebt - collateral * exchangeRate * liquidationThreshold)
        // repayDen = (targetHealth - (liquidationThreshold / (1 - discount)))
        // repay = repayNum / repayDen
        // repayNum = [rad].mulDiv([ray], [ray]) - ([wad] * [ray]).mulDiv([ray], [ray]) = [rad] - [rad] = [rad]
        // repayDen = [ray] - [ray].mulDiv(RAY, [ray]) = [ray] - [ray] = [ray]
        // repay = [rad].mulDiv(RAY, [ray]) = [rad]

        uint256 repayNum = debtValue.rayMulUp(TARGET_HEALTH) - collateralValue; // [rad] - [rad] = [rad]
        uint256 repayDen = TARGET_HEALTH - liquidationThreshold.rayDivUp(RAY - discount); // round up in protocol favor
        repay = repayNum.rayDivUp(repayDen);
    }

    struct LiquidateArgs {
        uint256 repay;
        uint256 gemOut;
        uint256 dart;
        uint256 fee;
        uint256 price;
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

        // needs ink art rate dust
        // TODO: multiple external calls vs. calling one getter that returns all
        uint256 collateral = ionPool.collateral(ilkIndex, vault);
        uint256 normalizedDebt = ionPool.normalizedDebt(ilkIndex, vault);
        uint256 rate = ionPool.rate(ilkIndex);
        uint256 dust = ionPool.dust(ilkIndex);

        (uint256 liquidationThreshold, uint256 exchangeRate) = _getExchangeRateAndLiquidationThreshold(ilkIndex);

        if (exchangeRate == 0) {
            revert ExchangeRateCannotBeZero(exchangeRate);
        }
        if (liquidationThreshold == 0) {
            revert LiquidationThresholdCannotBeZero(liquidationThreshold);
        }

        // collateralValue = collateral * exchangeRate * liquidationThreshold
        // debtValue = normalizedDebt * rate
        // healthRatio = collateralValue / debtValue
        // collateralValue = [wad] * [ray] * [ray] / RAY = [rad]
        // debtValue = [wad] * [ray] = [rad]
        // healthRatio = [rad] * RAY / [rad] = [ray]

        uint256 collateralValue = (collateral * exchangeRate).rayMulUp(liquidationThreshold); // round down in protocol
            // favor
        // uint256 debtValue = normalizedDebt * rate; stack overflow without

        {
            // [rad] * RAY / [rad] = [ray]
            uint256 healthRatio = collateralValue.rayDivDown(normalizedDebt * rate); // round down in protocol favor
            if (healthRatio >= RAY) {
                revert VaultIsNotUnsafe(healthRatio);
            }

            uint256 discount = RESERVE_FACTOR + (RAY - healthRatio); // [ray] + ([ray] - [ray])
            discount = discount <= MAX_DISCOUNT ? discount : MAX_DISCOUNT; // cap discount to maxDiscount

            liquidateArgs.price = exchangeRate.rayMulUp(RAY - discount); // [ray] * (RAY - [ray]) / [ray] = [ray], ETH
                // price per LST, round up in protocol favor
            liquidateArgs.repay = _getRepayAmt(normalizedDebt * rate, collateralValue, liquidationThreshold, discount);
        }

        // --- Calculating Repay ---

        // in protocol favor to round up repayNum, round down repayDen

        // --- Conditionals ---

        // First branch: full liquidation
        //    if repay > total debt, more debt needs to be paid off than available to go back to target health
        //    Move exactly all collateral and debt to the vow.
        //    Keeper pays gas but is otherwise left untouched.
        // Second branch: resulting debt is below dust
        //    There is enough collateral to cover the debt and go back to target health,
        //    but it would leave a debt amount less than dust.
        //    Force keeper to pay off all debt including dust and readjust the amount of collateral to sell.
        //    Resulting debt is zero.
        // Third branch: soft liquidation to target health ratio
        //    There is enough collateral to be sold to pay off debt.
        //    The resulting health ratio equals targetHealthRatio.

        // NOTE: could also add gemOut > collateral check
        if (liquidateArgs.repay > normalizedDebt * rate) {
            // [rad] > [rad]
            liquidateArgs.dart = normalizedDebt; // [wad]
            liquidateArgs.gemOut = collateral; // [wad]
            ionPool.confiscateVault(
                ilkIndex,
                vault,
                PROTOCOL, // TODO: this should go to PROTOCOL multisig
                PROTOCOL, // TODO: this should go to PROTOCOL mul
                -int256(liquidateArgs.gemOut),
                -int256(liquidateArgs.dart)
            );
            // TODO: emit protocol liquidation event
            return;
        } else if (normalizedDebt * rate - liquidateArgs.repay < dust) {
            // [rad] - [rad] < [rad]
            liquidateArgs.repay = normalizedDebt * rate; // bound repay to total debt
            liquidateArgs.dart = normalizedDebt; // pay off all debt including dust
            liquidateArgs.gemOut = normalizedDebt * rate / liquidateArgs.price; // round down in protocol favor
        } else {
            // if (normalizedDebt * rate - liquidateArgs.repay >= dust) do partial liquidation
            // repay stays unchanged
            liquidateArgs.dart = liquidateArgs.repay / rate; // [rad] / [ray] = [wad]
            liquidateArgs.dart =
                liquidateArgs.dart * rate < liquidateArgs.repay ? liquidateArgs.dart + 1 : liquidateArgs.dart; // round up
                // in protocol favor
            liquidateArgs.gemOut = liquidateArgs.repay / liquidateArgs.price; // readjust amount of collateral, round
                // down in protocol favor
        }

        // --- For Second and Third Branch ---

        // if dust, repay = normalizedDebt * rate
        // if partial, repay is unadjusted
        // TODO: simplify with mulmod
        uint256 transferAmt = (liquidateArgs.repay / RAY);
        transferAmt = transferAmt * RAY < liquidateArgs.repay ? transferAmt + 1 : transferAmt;

        // calculate fee
        liquidateArgs.fee = liquidateArgs.gemOut.rayMulUp(RESERVE_FACTOR); // [wad] * [ray] / [ray] = [wad]
        // transfer WETH from keeper to this contract
        underlying.safeTransferFrom(msg.sender, address(this), transferAmt);
        // take the debt to pay off and the collateral to sell from the vault
        // TODO: check for integer overflows
        ionPool.confiscateVault(
            ilkIndex, vault, address(this), address(this), -int256(liquidateArgs.gemOut), -int256(liquidateArgs.dart)
        );
        // pay off this contract's debt
        ionPool.repayBadDebt(address(this), liquidateArgs.repay);
        // send fee to the REVENUE_RECIPIENT
        ionPool.transferGem(ilkIndex, address(this), REVENUE_RECIPIENT, liquidateArgs.fee);
        // send the collateral sold to the keeper
        ionPool.transferGem(ilkIndex, address(this), kpr, liquidateArgs.gemOut - liquidateArgs.fee);

        emit Liquidate(kpr, liquidateArgs.repay, liquidateArgs.gemOut - liquidateArgs.fee, liquidateArgs.fee);
    }
}
