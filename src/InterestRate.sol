// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IInterestRate } from "./interfaces/IInterestRate.sol";
import { IYieldOracle } from "./interfaces/IYieldOracle.sol";
import { RoundedMath, RAY } from "../src/math/RoundedMath.sol";
import { IonPool } from "../src/IonPool.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

struct IlkData {
    // Max 4722E18                                     _
    uint72 adjustedProfitMargin; // 18 decimals         |
    // Max 6.5536                                       |
    uint16 adjustedReserveFactor; // 4 decimals         |
    // Max 1677E4                                       |
    uint24 adjustedAboveKinkSlope; // 4 decimals        |   256 bits
    // Max 4722E18                                      |
    uint72 adjustedBaseRate; // 18 decimals             |
    // Max 4722E18                                      |
    uint72 minimumKinkRate; // 18 decimals             _|
    // Max 4722E18                                      |
    uint72 minimumProfitMargin; // 18 decimals          |
    // Max ~6.5536; Should always be less than 1        |
    uint16 minimumReserveFactor; // 4 decimals          |
    // Max 1677E4                                       |   216 bits
    uint24 minimumAboveKinkSlope; // 4 decimals         |
    // Max 4722E18                                      |
    uint72 minimumBaseRate; // 18 decimals              |
    uint16 optimalUtilizationRate; // 2 decimals        |
    uint16 distributionFactor; // 2 decimals           _|
}

// forgefmt: disable-start

// Word 1
//
//                                                256                184              112   88  72                 0
//                                                 |                  |                |     |   | a_profit_margin |
//                                                    min_kink_rate        a_base_rate     ^    ^
//                                                                                         ^    a_reserve_factor
//                                                                         a_above_kink_slope

uint256 constant ADJUSTED_PROFIT_MARGIN_MASK =    0x0000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFF; 
uint256 constant ADJUSTED_RESERVE_FACTOR_MASK =   0x000000000000000000000000000000000000000000FFFF000000000000000000; 
uint256 constant ADJUSTED_ABOVE_KINK_SLOPE_MASK = 0x000000000000000000000000000000000000FFFFFF0000000000000000000000;
uint256 constant ADJUSTED_BASE_RATE_MASK =        0x000000000000000000FFFFFFFFFFFFFFFFFF0000000000000000000000000000;
uint256 constant MINIMUM_KINK_RATE_MASK =         0xFFFFFFFFFFFFFFFFFF0000000000000000000000000000000000000000000000;

// Word 2
//
//                                                256       216  200  184              112   88  72                 0
//                                                 |         |    |uopt|                |     |   |min_profit_margin|
//                                                              ^        min_base_rate     ^    ^
//                                               distribution_factor                       ^    min_reserve_factor
//                                                                       min_above_kink_slope

uint256 constant MINIMUM_PROFIT_MARGIN_MASK =     0x0000000000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFF;
uint256 constant MINIMUM_RESERVE_FACTOR_MASK =    0x000000000000000000000000000000000000000000FFFF000000000000000000;
uint256 constant MINIMUM_ABOVE_KINK_SLOPE_MASK =  0x000000000000000000000000000000000000FFFFFF0000000000000000000000;
uint256 constant MINIMUM_BASE_RATE_MASK =         0x000000000000000000FFFFFFFFFFFFFFFFFF0000000000000000000000000000;
uint256 constant OPTIMAL_UTILIZATION_MASK =       0x00000000000000FFFF0000000000000000000000000000000000000000000000;
uint256 constant DISTRIBUTION_FACTOR_MASK =       0x0000000000FFFF00000000000000000000000000000000000000000000000000;

// forgefmt: disable-end

// Word 1
uint8 constant ADJUSTED_PROFIT_MARGIN_SHIFT = 0;
uint8 constant ADJUSTED_RESERVE_FACTOR_SHIFT = 72;
uint8 constant ADJUSTED_ABOVE_KINK_SLOPE_SHIFT = 72 + 16;
uint8 constant ADJUSTED_BASE_RATE_SHIFT = 72 + 16 + 24;
uint8 constant MINIMUM_KINK_RATE_SHIFT = 72 + 16 + 24 + 72;

// Word 2
uint8 constant MINIMUM_PROFIT_MARGIN_SHIFT = 0;
uint8 constant MINIMUM_RESERVE_FACTOR_SHIFT = 72;
uint8 constant MINIMUM_ABOVE_KINK_SLOPE_SHIFT = 72 + 16;
uint8 constant MINIMUM_BASE_RATE_SHIFT = 72 + 16 + 24;
uint8 constant OPTIMAL_UTILIZATION_SHIFT = 72 + 16 + 24 + 72;
uint8 constant DISTRIBUTION_FACTOR_SHIFT = 72 + 16 + 24 + 72 + 16;

uint256 constant SECONDS_IN_A_DAY = 31_536_000;

contract InterestRate {
    error DistributionFactorsDoNotSumToOne(uint256 sum);

    using RoundedMath for uint256;

    error CollateralIndexOutOfBounds();
    error TotalDebtsLength(uint256 collateralCount, uint256 totalDebtsLength);

    /**
     * @dev Packed collateral configs
     */
    uint256 internal immutable ilkConfig0_a;
    uint256 internal immutable ilkConfig0_b;
    uint256 internal immutable ilkConfig1_a;
    uint256 internal immutable ilkConfig1_b;
    uint256 internal immutable ilkConfig2_a;
    uint256 internal immutable ilkConfig2_b;
    uint256 internal immutable ilkConfig3_a;
    uint256 internal immutable ilkConfig3_b;
    uint256 internal immutable ilkConfig4_a;
    uint256 internal immutable ilkConfig4_b;
    uint256 internal immutable ilkConfig5_a;
    uint256 internal immutable ilkConfig5_b;
    uint256 internal immutable ilkConfig6_a;
    uint256 internal immutable ilkConfig6_b;
    uint256 internal immutable ilkConfig7_a;
    uint256 internal immutable ilkConfig7_b;

    uint256 public immutable collateralCount;
    IYieldOracle immutable apyOracle;

    constructor(IlkData[] memory ilkDataList, IYieldOracle _apyOracle) {
        collateralCount = ilkDataList.length;
        apyOracle = _apyOracle;

        uint256 distributionFactorSum = 0;
        for (uint256 i = 0; i < ilkDataList.length;) {
            distributionFactorSum += ilkDataList[i].distributionFactor;

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }
        if (distributionFactorSum != 1e2) revert DistributionFactorsDoNotSumToOne(distributionFactorSum);

        (ilkConfig0_a, ilkConfig0_b) = _packCollateralConfig(ilkDataList, 0);
        (ilkConfig1_a, ilkConfig1_b) = _packCollateralConfig(ilkDataList, 1);
        (ilkConfig2_a, ilkConfig2_b) = _packCollateralConfig(ilkDataList, 2);
        (ilkConfig3_a, ilkConfig3_b) = _packCollateralConfig(ilkDataList, 3);
        (ilkConfig4_a, ilkConfig4_b) = _packCollateralConfig(ilkDataList, 4);
        (ilkConfig5_a, ilkConfig5_b) = _packCollateralConfig(ilkDataList, 5);
        (ilkConfig6_a, ilkConfig6_b) = _packCollateralConfig(ilkDataList, 6);
        (ilkConfig7_a, ilkConfig7_b) = _packCollateralConfig(ilkDataList, 7);
    }

    function _packCollateralConfig(
        IlkData[] memory ilkDataList,
        uint256 index
    )
        internal
        view
        returns (uint256 packedConfig_a, uint256 packedConfig_b)
    {
        if (index >= collateralCount) return (0, 0);

        IlkData memory ilkData = ilkDataList[index];

        packedConfig_a = (
            uint256(ilkData.adjustedProfitMargin) << ADJUSTED_PROFIT_MARGIN_MASK
                | uint256(ilkData.adjustedReserveFactor) << ADJUSTED_RESERVE_FACTOR_MASK
                | uint256(ilkData.adjustedAboveKinkSlope) << ADJUSTED_ABOVE_KINK_SLOPE_MASK
                | uint256(ilkData.adjustedBaseRate) << ADJUSTED_BASE_RATE_MASK
                | uint256(ilkData.minimumKinkRate) << MINIMUM_KINK_RATE_MASK
        );

        packedConfig_b = (
            uint256(ilkData.minimumProfitMargin) << MINIMUM_PROFIT_MARGIN_MASK
                | uint256(ilkData.minimumReserveFactor) << MINIMUM_RESERVE_FACTOR_MASK
                | uint256(ilkData.minimumAboveKinkSlope) << MINIMUM_ABOVE_KINK_SLOPE_MASK
                | uint256(ilkData.minimumBaseRate) << MINIMUM_BASE_RATE_MASK
                | uint256(ilkData.optimalUtilizationRate) << OPTIMAL_UTILIZATION_MASK
                | uint256(ilkData.distributionFactor) << DISTRIBUTION_FACTOR_MASK
        );
    }

    function _unpackCollateralConfig(uint256 index) internal view returns (IlkData memory ilkData) {
        if (index > collateralCount - 1) revert CollateralIndexOutOfBounds();

        uint256 packedConfig_a;
        uint256 packedConfig_b;

        if (index == 0) {
            packedConfig_a = ilkConfig0_a;
            packedConfig_b = ilkConfig0_b;
        } else if (index == 1) {
            packedConfig_a = ilkConfig1_a;
            packedConfig_b = ilkConfig0_b;
        } else if (index == 2) {
            packedConfig_a = ilkConfig2_a;
            packedConfig_b = ilkConfig1_b;
        } else if (index == 3) {
            packedConfig_a = ilkConfig3_a;
            packedConfig_b = ilkConfig1_b;
        } else if (index == 4) {
            packedConfig_a = ilkConfig4_a;
            packedConfig_b = ilkConfig2_b;
        } else if (index == 5) {
            packedConfig_a = ilkConfig5_a;
            packedConfig_b = ilkConfig2_b;
        } else if (index == 6) {
            packedConfig_a = ilkConfig6_a;
            packedConfig_b = ilkConfig3_b;
        } else if (index == 7) {
            packedConfig_a = ilkConfig7_a;
            packedConfig_b = ilkConfig3_b;
        }

        uint72 adjustedProfitMargin =
            uint72((packedConfig_a & ADJUSTED_PROFIT_MARGIN_MASK) >> ADJUSTED_PROFIT_MARGIN_SHIFT);
        uint16 adjustedReserveFactor =
            uint16((packedConfig_a & ADJUSTED_RESERVE_FACTOR_MASK) >> ADJUSTED_RESERVE_FACTOR_SHIFT);
        uint24 adjustedAboveKinkSlope =
            uint24((packedConfig_a & ADJUSTED_ABOVE_KINK_SLOPE_MASK) >> ADJUSTED_ABOVE_KINK_SLOPE_SHIFT);
        uint72 adjustedBaseRate = uint72((packedConfig_a & ADJUSTED_BASE_RATE_MASK) >> ADJUSTED_BASE_RATE_SHIFT);
        uint72 minimumKinkRate = uint72((packedConfig_a & MINIMUM_KINK_RATE_MASK) >> MINIMUM_KINK_RATE_SHIFT);

        uint72 minimumProfitMargin =
            uint72((packedConfig_b & MINIMUM_PROFIT_MARGIN_MASK) >> MINIMUM_PROFIT_MARGIN_SHIFT);
        uint16 minimumReserveFactor =
            uint16((packedConfig_b & MINIMUM_RESERVE_FACTOR_MASK) >> MINIMUM_RESERVE_FACTOR_SHIFT);
        uint24 minimumAboveKinkSlope =
            uint24((packedConfig_b & MINIMUM_ABOVE_KINK_SLOPE_MASK) >> MINIMUM_ABOVE_KINK_SLOPE_SHIFT);
        uint72 minimumBaseRate = uint72((packedConfig_b & MINIMUM_BASE_RATE_MASK) >> MINIMUM_BASE_RATE_SHIFT);
        uint16 optimalUtilizationRate = uint16((packedConfig_b & OPTIMAL_UTILIZATION_MASK) >> OPTIMAL_UTILIZATION_SHIFT);
        uint16 distributionFactor = uint16((packedConfig_b & DISTRIBUTION_FACTOR_MASK) >> DISTRIBUTION_FACTOR_SHIFT);

        ilkData = IlkData({
            adjustedProfitMargin: adjustedProfitMargin,
            adjustedReserveFactor: adjustedReserveFactor,
            adjustedAboveKinkSlope: adjustedAboveKinkSlope,
            adjustedBaseRate: adjustedBaseRate,
            minimumKinkRate: minimumKinkRate,
            minimumProfitMargin: minimumProfitMargin,
            minimumReserveFactor: minimumReserveFactor,
            minimumAboveKinkSlope: minimumAboveKinkSlope,
            minimumBaseRate: minimumBaseRate,
            optimalUtilizationRate: optimalUtilizationRate,
            distributionFactor: distributionFactor
        });
    }

    /**
     * @param ilkIndex index of the collateral
     * @param totalDebt total debt of the system (27 decimals)
     * @param totalEthSupply total eth supply of the system (18 decimals)
     */
    function calculateInterestRate(
        uint256 ilkIndex,
        uint256 totalDebt, // [RAY]
        uint256 totalEthSupply
    )
        external
        view
        returns (uint256 borrowRate, uint256 reserveFactor)
    {
        IlkData memory ilkData = _unpackCollateralConfig(ilkIndex);

        // TODO: Validate input
        uint256 collateralApy = apyOracle.apys(ilkIndex);

        uint256 distributionFactorRay = _scaleToRay(ilkData.distributionFactor, 2);
        uint256 collateralApyRay = _scaleToRay(collateralApy, 6);
        uint256 optimalUtilizationRateRay = _scaleToRay(ilkData.optimalUtilizationRate, 18);
        totalEthSupply = _scaleToRay(totalEthSupply, 18);

        uint256 collateralApyRayInSeconds = collateralApyRay.rayDivDown(SECONDS_IN_A_DAY * RAY);

        // uint256 slope = (collateralApyRayInSeconds - profitMarginRay).rayDivDown(optimalUtilizationRateRay);
        uint256 utilizationRate =
            totalEthSupply == 0 ? 0 : totalDebt.rayDivDown(totalEthSupply.rayMulDown(distributionFactorRay));

        uint256 profitMarginRay = _scaleToRay(ilkData.adjustedProfitMargin, 18);

        uint256 adjustedBaseRateRay = _scaleToRay(ilkData.adjustedBaseRate, 18);
        uint256 adjustedBelowKinkSlope =
            (collateralApyRayInSeconds - profitMarginRay - adjustedBaseRateRay).rayDivDown(optimalUtilizationRateRay);

        uint256 minimumBaseRateRay = _scaleToRay(ilkData.minimumBaseRate, 18);
        uint256 minimumBelowKinkSlope =
            _scaleToRay(ilkData.minimumKinkRate - ilkData.minimumBaseRate, 18).rayDivDown(optimalUtilizationRateRay);

        if (utilizationRate < optimalUtilizationRateRay) {
            uint256 adjustedBorrowRate = adjustedBelowKinkSlope.rayMulDown(utilizationRate) + adjustedBaseRateRay;
            uint256 minimumBorrowRate = minimumBelowKinkSlope.rayMulDown(utilizationRate) + minimumBaseRateRay;

            if (adjustedBorrowRate < minimumBorrowRate) {
                borrowRate = minimumBorrowRate;
                reserveFactor = ilkData.minimumReserveFactor;
            } else {
                borrowRate = adjustedBorrowRate;
                reserveFactor = ilkData.adjustedReserveFactor;
            }
        } else {
            uint256 excessUtil = utilizationRate - optimalUtilizationRateRay;

            uint256 adjustedNormalRate =
                adjustedBelowKinkSlope.rayMulDown(optimalUtilizationRateRay) + adjustedBaseRateRay;
            uint256 minimumNormalRate = minimumBelowKinkSlope.rayMulDown(optimalUtilizationRateRay) + minimumBaseRateRay;

            // [WAD] * [RAY] / [WAD] = [RAY]
            uint256 adjustedBorrowRate =
                uint256(ilkData.adjustedAboveKinkSlope).wadMulDown(excessUtil) + adjustedNormalRate;
            uint256 minimumBorrowRate =
                uint256(ilkData.minimumAboveKinkSlope).wadMulDown(excessUtil) + minimumNormalRate;

            if (adjustedBorrowRate < minimumBorrowRate) {
                borrowRate = minimumBorrowRate;
                reserveFactor = ilkData.minimumReserveFactor;
            } else {
                borrowRate = adjustedBorrowRate;
                reserveFactor = ilkData.adjustedReserveFactor;
            }
        }
    }

    function _scaleToRay(uint256 value, uint256 scale) internal pure returns (uint256) {
        return value * (10 ** 27) / (10 ** scale);
    }
}
