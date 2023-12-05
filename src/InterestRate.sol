// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IYieldOracle } from "./interfaces/IYieldOracle.sol";
import { WadRayMath } from "./libraries/math/WadRayMath.sol";

// forgefmt: disable-start

struct IlkData {
    // Word 1
    uint96 adjustedProfitMargin; // 27 decimals
    uint96 minimumKinkRate; // 27 decimals

    // Word 2
    uint16 reserveFactor; // 4 decimals
    uint96 adjustedBaseRate; // 27 decimals
    uint96 minimumBaseRate; // 27 decimals
    uint16 optimalUtilizationRate; // 4 decimals
    uint16 distributionFactor; // 4 decimals

    // Word 3
    uint96 adjustedAboveKinkSlope; // 27 decimals
    uint96 minimumAboveKinkSlope; // 27 decimals
}

// Word 1
//
//                                                256  240   216   192                     96                      0
//                                                 |    |     |     |     min_kink_rate     |   adj_profit_margin  |
//
uint256 constant ADJUSTED_PROFIT_MARGIN_MASK =    0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF; 
uint256 constant MINIMUM_KINK_RATE_MASK =         0x0000000000000000FFFFFFFFFFFFFFFFFFFFFFFF000000000000000000000000;

// Word 2
//
//                                                256  240 224 208                     112                     16   0
//                                                 | __ |   |   |     min_base_rate     |     adj_base_rate     |   |
//                                                        ^   ^                                                   ^
//                                                        ^  opt_util                                 reserve_factor
//                                       distribution_factor

uint256 constant RESERVE_FACTOR_MASK =            0x000000000000000000000000000000000000000000000000000000000000FFFF;
uint256 constant ADJUSTED_BASE_RATE_MASK =        0x000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF0000;
uint256 constant MINIMUM_BASE_RATE_MASK =         0x000000000000FFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000;
uint256 constant OPTIMAL_UTILIZATION_MASK =       0x00000000FFFF0000000000000000000000000000000000000000000000000000;
uint256 constant DISTRIBUTION_FACTOR_MASK =       0x0000FFFF00000000000000000000000000000000000000000000000000000000;

// Word 3
//                                                256  240   216   192                     96                      0
//                                                 |    |     |     |  min_above_kink_slope | adj_above_kink_slope |
//
uint256 constant ADJUSTED_ABOVE_KINK_SLOPE_MASK =  0x0000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;
uint256 constant MINIMUM_ABOVE_KINK_SLOPE_MASK =   0x0000000000000000FFFFFFFFFFFFFFFFFFFFFFFF000000000000000000000000; 

// forgefmt: disable-end

// Word 1
uint8 constant ADJUSTED_PROFIT_MARGIN_SHIFT = 0;
uint8 constant MINIMUM_KINK_RATE_SHIFT = 96;

// Word 2
uint8 constant RESERVE_FACTOR_SHIFT = 0;
uint8 constant ADJUSTED_BASE_RATE_SHIFT = 16;
uint8 constant MINIMUM_BASE_RATE_SHIFT = 16 + 96;
uint8 constant OPTIMAL_UTILIZATION_SHIFT = 16 + 96 + 96;
uint8 constant DISTRIBUTION_FACTOR_SHIFT = 16 + 96 + 96 + 16;

// Word 3
uint8 constant ADJUSTED_ABOVE_KINK_SLOPE_SHIFT = 0;
uint8 constant MINIMUM_ABOVE_KINK_SLOPE_SHIFT = 96;

uint48 constant SECONDS_IN_A_YEAR = 31_536_000;

contract InterestRate {
    using WadRayMath for *;

    error CollateralIndexOutOfBounds();
    error DistributionFactorsDoNotSumToOne(uint256 sum);
    error TotalDebtsLength(uint256 COLLATERAL_COUNT, uint256 totalIlkDebtsLength);
    error InvalidYieldOracleAddress();

    /**
     * @dev Packed collateral configs
     */
    uint256 internal immutable ILKCONFIG_0A;
    uint256 internal immutable ILKCONFIG_0B;
    uint256 internal immutable ILKCONFIG_0C;
    uint256 internal immutable ILKCONFIG_1A;
    uint256 internal immutable ILKCONFIG_1B;
    uint256 internal immutable ILKCONFIG_1C;
    uint256 internal immutable ILKCONFIG_2A;
    uint256 internal immutable ILKCONFIG_2B;
    uint256 internal immutable ILKCONFIG_2C;
    uint256 internal immutable ILKCONFIG_3A;
    uint256 internal immutable ILKCONFIG_3B;
    uint256 internal immutable ILKCONFIG_3C;
    uint256 internal immutable ILKCONFIG_4A;
    uint256 internal immutable ILKCONFIG_4B;
    uint256 internal immutable ILKCONFIG_4C;
    uint256 internal immutable ILKCONFIG_5A;
    uint256 internal immutable ILKCONFIG_5B;
    uint256 internal immutable ILKCONFIG_5C;
    uint256 internal immutable ILKCONFIG_6A;
    uint256 internal immutable ILKCONFIG_6B;
    uint256 internal immutable ILKCONFIG_6C;
    uint256 internal immutable ILKCONFIG_7A;
    uint256 internal immutable ILKCONFIG_7B;
    uint256 internal immutable ILKCONFIG_7C;

    uint256 public immutable COLLATERAL_COUNT;
    IYieldOracle public immutable YIELD_ORACLE;

    constructor(IlkData[] memory ilkDataList, IYieldOracle _yieldOracle) {
        if (address(_yieldOracle) == address(0)) revert InvalidYieldOracleAddress();

        COLLATERAL_COUNT = ilkDataList.length;
        YIELD_ORACLE = _yieldOracle;

        uint256 distributionFactorSum = 0;
        for (uint256 i = 0; i < COLLATERAL_COUNT;) {
            distributionFactorSum += ilkDataList[i].distributionFactor;

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }

        if (distributionFactorSum != 1e4) revert DistributionFactorsDoNotSumToOne(distributionFactorSum);

        (ILKCONFIG_0A, ILKCONFIG_0B, ILKCONFIG_0C) = _packCollateralConfig(ilkDataList, 0);
        (ILKCONFIG_1A, ILKCONFIG_1B, ILKCONFIG_1C) = _packCollateralConfig(ilkDataList, 1);
        (ILKCONFIG_2A, ILKCONFIG_2B, ILKCONFIG_2C) = _packCollateralConfig(ilkDataList, 2);
        (ILKCONFIG_3A, ILKCONFIG_3B, ILKCONFIG_3C) = _packCollateralConfig(ilkDataList, 3);
        (ILKCONFIG_4A, ILKCONFIG_4B, ILKCONFIG_4C) = _packCollateralConfig(ilkDataList, 4);
        (ILKCONFIG_5A, ILKCONFIG_5B, ILKCONFIG_5C) = _packCollateralConfig(ilkDataList, 5);
        (ILKCONFIG_6A, ILKCONFIG_6B, ILKCONFIG_6C) = _packCollateralConfig(ilkDataList, 6);
        (ILKCONFIG_7A, ILKCONFIG_7B, ILKCONFIG_7C) = _packCollateralConfig(ilkDataList, 7);
    }

    function _packCollateralConfig(
        IlkData[] memory ilkDataList,
        uint256 index
    )
        internal
        view
        returns (uint256 packedConfig_a, uint256 packedConfig_b, uint256 packedConfig_c)
    {
        if (index >= COLLATERAL_COUNT) return (0, 0, 0);

        IlkData memory ilkData = ilkDataList[index];

        packedConfig_a = (
            uint256(ilkData.adjustedProfitMargin) << ADJUSTED_PROFIT_MARGIN_SHIFT
                | uint256(ilkData.minimumKinkRate) << MINIMUM_KINK_RATE_SHIFT
        );

        packedConfig_b = (
            uint256(ilkData.reserveFactor) << RESERVE_FACTOR_SHIFT
                | uint256(ilkData.adjustedBaseRate) << ADJUSTED_BASE_RATE_SHIFT
                | uint256(ilkData.minimumBaseRate) << MINIMUM_BASE_RATE_SHIFT
                | uint256(ilkData.optimalUtilizationRate) << OPTIMAL_UTILIZATION_SHIFT
                | uint256(ilkData.distributionFactor) << DISTRIBUTION_FACTOR_SHIFT
        );

        packedConfig_c = (
            uint256(ilkData.adjustedAboveKinkSlope) << ADJUSTED_ABOVE_KINK_SLOPE_SHIFT
                | uint256(ilkData.minimumAboveKinkSlope) << MINIMUM_ABOVE_KINK_SLOPE_SHIFT
        );
    }

    function unpackCollateralConfig(uint256 index) external view returns (IlkData memory ilkData) {
        ilkData = _unpackCollateralConfig(index);
    }

    function _unpackCollateralConfig(uint256 index) internal view returns (IlkData memory ilkData) {
        if (index > COLLATERAL_COUNT - 1) revert CollateralIndexOutOfBounds();

        uint256 packedConfig_a;
        uint256 packedConfig_b;
        uint256 packedConfig_c;

        if (index == 0) {
            packedConfig_a = ILKCONFIG_0A;
            packedConfig_b = ILKCONFIG_0B;
            packedConfig_c = ILKCONFIG_0C;
        } else if (index == 1) {
            packedConfig_a = ILKCONFIG_1A;
            packedConfig_b = ILKCONFIG_1B;
            packedConfig_c = ILKCONFIG_1C;
        } else if (index == 2) {
            packedConfig_a = ILKCONFIG_2A;
            packedConfig_b = ILKCONFIG_2B;
            packedConfig_c = ILKCONFIG_2C;
        } else if (index == 3) {
            packedConfig_a = ILKCONFIG_3A;
            packedConfig_b = ILKCONFIG_3B;
            packedConfig_c = ILKCONFIG_3C;
        } else if (index == 4) {
            packedConfig_a = ILKCONFIG_4A;
            packedConfig_b = ILKCONFIG_4B;
            packedConfig_c = ILKCONFIG_4C;
        } else if (index == 5) {
            packedConfig_a = ILKCONFIG_5A;
            packedConfig_b = ILKCONFIG_5B;
            packedConfig_c = ILKCONFIG_5C;
        } else if (index == 6) {
            packedConfig_a = ILKCONFIG_6A;
            packedConfig_b = ILKCONFIG_6B;
            packedConfig_c = ILKCONFIG_6C;
        } else if (index == 7) {
            packedConfig_a = ILKCONFIG_7A;
            packedConfig_b = ILKCONFIG_7B;
            packedConfig_c = ILKCONFIG_7C;
        }

        uint96 adjustedProfitMargin =
            uint96((packedConfig_a & ADJUSTED_PROFIT_MARGIN_MASK) >> ADJUSTED_PROFIT_MARGIN_SHIFT);
        uint96 minimumKinkRate = uint96((packedConfig_a & MINIMUM_KINK_RATE_MASK) >> MINIMUM_KINK_RATE_SHIFT);

        uint16 reserveFactor = uint16((packedConfig_b & RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_SHIFT);
        uint96 adjustedBaseRate = uint96((packedConfig_b & ADJUSTED_BASE_RATE_MASK) >> ADJUSTED_BASE_RATE_SHIFT);
        uint96 minimumBaseRate = uint96((packedConfig_b & MINIMUM_BASE_RATE_MASK) >> MINIMUM_BASE_RATE_SHIFT);
        uint16 optimalUtilizationRate = uint16((packedConfig_b & OPTIMAL_UTILIZATION_MASK) >> OPTIMAL_UTILIZATION_SHIFT);
        uint16 distributionFactor = uint16((packedConfig_b & DISTRIBUTION_FACTOR_MASK) >> DISTRIBUTION_FACTOR_SHIFT);

        uint96 adjustedAboveKinkSlope =
            uint96((packedConfig_c & ADJUSTED_ABOVE_KINK_SLOPE_MASK) >> ADJUSTED_ABOVE_KINK_SLOPE_SHIFT);
        uint96 minimumAboveKinkSlope =
            uint96((packedConfig_c & MINIMUM_ABOVE_KINK_SLOPE_MASK) >> MINIMUM_ABOVE_KINK_SLOPE_SHIFT);

        ilkData = IlkData({
            adjustedProfitMargin: adjustedProfitMargin,
            minimumKinkRate: minimumKinkRate,
            reserveFactor: reserveFactor,
            adjustedBaseRate: adjustedBaseRate,
            minimumBaseRate: minimumBaseRate,
            optimalUtilizationRate: optimalUtilizationRate,
            distributionFactor: distributionFactor,
            adjustedAboveKinkSlope: adjustedAboveKinkSlope,
            minimumAboveKinkSlope: minimumAboveKinkSlope
        });
    }

    /**
     * @param ilkIndex index of the collateral
     * @param totalIlkDebt total debt of the collateral (45 decimals)
     * @param totalEthSupply total eth supply of the system (18 decimals)
     */
    function calculateInterestRate(
        uint256 ilkIndex,
        uint256 totalIlkDebt, // [RAD]
        uint256 totalEthSupply
    )
        external
        view
        returns (uint256, uint256)
    {
        IlkData memory ilkData = _unpackCollateralConfig(ilkIndex);
        uint256 optimalUtilizationRateRay = ilkData.optimalUtilizationRate.scaleUpToRay(4);
        uint256 collateralApyRayInSeconds = YIELD_ORACLE.apys(ilkIndex).scaleUpToRay(8) / SECONDS_IN_A_YEAR;

        uint256 distributionFactor = ilkData.distributionFactor;
        // The only time the distribution factor will be set to 0 is when a
        // market has been sunset. In this case, we want to prevent division by
        // 0, but we also want to prevent the borrow rate from skyrocketing. So
        // we will return a reasonable borrow rate of kink utilization on the
        // minimum curve.
        if (distributionFactor == 0) {
            return (ilkData.minimumKinkRate, ilkData.reserveFactor.scaleUpToRay(4));
        }
        // [RAD] / [WAD] = [RAY]
        uint256 utilizationRate =
            totalEthSupply == 0 ? 0 : totalIlkDebt / (totalEthSupply.wadMulDown(distributionFactor.scaleUpToWad(4)));

        // Avoid stack too deep
        uint256 adjustedBelowKinkSlope;
        {
            uint256 slopeNumerator;
            unchecked {
                slopeNumerator = collateralApyRayInSeconds - ilkData.adjustedProfitMargin - ilkData.adjustedBaseRate;
            }

            // Underflow occured
            // If underflow occured, then the Apy was too low or the profitMargin was too high and
            // we would want to switch to minimum borrow rate. Set slopeNumerator to zero such
            // that adjusted borrow rate is below the minimum borrow rate.
            if (slopeNumerator > collateralApyRayInSeconds) {
                slopeNumerator = 0;
            }

            adjustedBelowKinkSlope = slopeNumerator.rayDivDown(optimalUtilizationRateRay);
        }

        uint256 minimumBelowKinkSlope =
            (ilkData.minimumKinkRate - ilkData.minimumBaseRate).rayDivDown(optimalUtilizationRateRay);

        // Below kink
        if (utilizationRate < optimalUtilizationRateRay) {
            uint256 adjustedBorrowRate = adjustedBelowKinkSlope.rayMulDown(utilizationRate) + ilkData.adjustedBaseRate;
            uint256 minimumBorrowRate = minimumBelowKinkSlope.rayMulDown(utilizationRate) + ilkData.minimumBaseRate;

            if (adjustedBorrowRate < minimumBorrowRate) {
                return (minimumBorrowRate, ilkData.reserveFactor.scaleUpToRay(4));
            } else {
                return (adjustedBorrowRate, ilkData.reserveFactor.scaleUpToRay(4));
            }
        }
        // Above kink
        else {
            // For the above kink calculation, we will use the below kink slope
            // for all utilization up until the kink. From that point on we will
            // use the above kink slope.
            uint256 excessUtil = utilizationRate - optimalUtilizationRateRay;

            uint256 adjustedNormalRate =
                adjustedBelowKinkSlope.rayMulDown(optimalUtilizationRateRay) + ilkData.adjustedBaseRate;
            uint256 minimumNormalRate =
                minimumBelowKinkSlope.rayMulDown(optimalUtilizationRateRay) + ilkData.minimumBaseRate;

            // [WAD] * [RAY] / [WAD] = [RAY]
            uint256 adjustedBorrowRate = ilkData.adjustedAboveKinkSlope.rayMulDown(excessUtil) + adjustedNormalRate;
            uint256 minimumBorrowRate = ilkData.minimumAboveKinkSlope.rayMulDown(excessUtil) + minimumNormalRate;

            if (adjustedBorrowRate < minimumBorrowRate) {
                return (minimumBorrowRate, ilkData.reserveFactor.scaleUpToRay(4));
            } else {
                return (adjustedBorrowRate, ilkData.reserveFactor.scaleUpToRay(4));
            }
        }
    }
}
