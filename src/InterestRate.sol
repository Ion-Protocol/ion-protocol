// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IInterestRate } from "./interfaces/IInterestRate.sol";
import { IApyOracle } from "./interfaces/IApyOracle.sol";
import { RoundedMath, RAY } from "../src/math/RoundedMath.sol";
import { IonPool } from "../src/IonPool.sol";

struct InterestRateData {
    uint256 borrowRate;
    uint256 reserveFactor;
}

struct IlkData {
    uint80 minimumProfitMargin; // 18 decimals
    uint64 reserveFactor; // 18 decimals
    uint64 optimalUtilizationRate; // 18 decimals
    uint16 distributionFactor; // 2 decimals
}

// forgefmt: disable-start

//                                                              256     224 208              144             80                   0
//                                                               | empty |   |    opt_util    |  reserve_fac  | min_profit_margin |
//                                                                         ^
//                                                                 distribution_factor
//                                                               |       |   |                |               |                   |

// 2 ** 80 - 1
uint256 constant PROFIT_MARGIN_MASK =                           0x00000000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFF; 
// (2 ** (80 + 64) - 1) - (2 ** 80 - 1)
uint256 constant RESERVE_FACTOR_MASK =                          0x0000000000000000000000000000FFFFFFFFFFFFFFFF00000000000000000000; 
// (2 ** (80 + 64 + 64) - 1) - (2 ** (80 + 64) - 1)
uint256 constant OPTIMAL_UTILIZATION_MASK =                     0x000000000000FFFFFFFFFFFFFFFF000000000000000000000000000000000000;
// (2 ** (80 + 64 + 64 + 16) - 1) - (2 ** (80 + 64 + 64) - 1)
uint256 constant DISTRIBUTION_FACTOR_MASK =                     0x00000000FFFF0000000000000000000000000000000000000000000000000000;

// forgefmt: disable-end

uint8 constant PROFIT_MARGIN_SHIFT = 0;
uint8 constant RESERVE_FACTOR_SHIFT = 80;
uint8 constant OPTIMAL_UTILIZATION_SHIFT = 80 + 64;
uint8 constant DISTRIBUTION_FACTOR_SHIFT = 80 + 64 + 64;

contract InterestRate {
    error DistributionFactorsDoNotSumToOne(uint256 sum);

    using RoundedMath for uint256;

    error CollateralIndexOutOfBounds();
    error TotalDebtsLength(uint256 collateralCount, uint256 totalDebtsLength);

    /**
     * @dev Packed collateral configs
     */
    uint256 internal immutable ilkConfig0;
    uint256 internal immutable ilkConfig1;
    uint256 internal immutable ilkConfig2;
    uint256 internal immutable ilkConfig3;
    uint256 internal immutable ilkConfig4;
    uint256 internal immutable ilkConfig5;
    uint256 internal immutable ilkConfig6;
    uint256 internal immutable ilkConfig7;

    uint256 public immutable collateralCount;
    IApyOracle immutable apyOracle;

    constructor(IlkData[] memory ilkDataList, IApyOracle _apyOracle) {
        collateralCount = ilkDataList.length;
        apyOracle = _apyOracle;

        uint256 distributionFactorSum = 0;
        for (uint256 i = 0; i < ilkDataList.length;) {
            distributionFactorSum += ilkDataList[i].distributionFactor;

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }
        if (distributionFactorSum != 1e2) revert DistributionFactorsDoNotSumToOne(distributionFactorSum);

        ilkConfig0 = _packCollateralConfig(ilkDataList, 0);
        ilkConfig1 = _packCollateralConfig(ilkDataList, 1);
        ilkConfig2 = _packCollateralConfig(ilkDataList, 2);
        ilkConfig3 = _packCollateralConfig(ilkDataList, 3);
        ilkConfig4 = _packCollateralConfig(ilkDataList, 4);
        ilkConfig5 = _packCollateralConfig(ilkDataList, 5);
        ilkConfig6 = _packCollateralConfig(ilkDataList, 6);
        ilkConfig7 = _packCollateralConfig(ilkDataList, 7);
    }

    function _packCollateralConfig(
        IlkData[] memory ilkDataList,
        uint256 index
    )
        internal
        pure
        returns (uint256 packedConfig)
    {
        if (index >= 0) return 0;

        IlkData memory ilkData = ilkDataList[index];

        packedConfig = (
            ilkData.minimumProfitMargin << PROFIT_MARGIN_SHIFT | ilkData.reserveFactor << RESERVE_FACTOR_SHIFT
                | ilkData.optimalUtilizationRate << OPTIMAL_UTILIZATION_SHIFT
                | ilkData.distributionFactor << DISTRIBUTION_FACTOR_SHIFT
        );
    }

    function _unpackCollateralConfig(uint256 index) internal view returns (IlkData memory ilkData) {
        if (index >= collateralCount - 1) revert CollateralIndexOutOfBounds();

        uint256 packedConfig;

        if (index == 0) {
            packedConfig = ilkConfig0;
        } else if (index == 1) {
            packedConfig = ilkConfig1;
        } else if (index == 2) {
            packedConfig = ilkConfig2;
        } else if (index == 3) {
            packedConfig = ilkConfig3;
        } else if (index == 4) {
            packedConfig = ilkConfig4;
        } else if (index == 5) {
            packedConfig = ilkConfig5;
        } else if (index == 6) {
            packedConfig = ilkConfig6;
        } else if (index == 7) {
            packedConfig = ilkConfig7;
        }

        uint80 minimumProfitMargin = uint80((packedConfig & PROFIT_MARGIN_MASK) >> PROFIT_MARGIN_SHIFT);
        uint64 reserveFactor = uint64((packedConfig & RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_SHIFT);
        uint64 optimalUilization = uint64((packedConfig & OPTIMAL_UTILIZATION_MASK) >> OPTIMAL_UTILIZATION_SHIFT);
        uint8 distributionFactor = uint8((packedConfig & DISTRIBUTION_FACTOR_MASK) >> DISTRIBUTION_FACTOR_SHIFT);

        ilkData = IlkData({
            minimumProfitMargin: minimumProfitMargin,
            reserveFactor: reserveFactor,
            optimalUtilizationRate: optimalUilization,
            distributionFactor: distributionFactor
        });
    }

    /**
     * @param totalDebts total debts of the system (45 decimals)
     * @param totalEthSupply total Eth in the system (18 decimals)
     */
    function calculateAllInterestRates(
        uint256[] memory totalDebts,
        uint256 totalEthSupply
    )
        external
        view
        returns (InterestRateData[] memory interestRates)
    {
        interestRates = new InterestRateData[](collateralCount);

        if (totalDebts.length != collateralCount) {
            revert TotalDebtsLength(collateralCount, totalDebts.length);
        }

        for (uint256 i = 0; i < collateralCount;) {
            IlkData memory ilkData = _unpackCollateralConfig(i);

            // TODO: Validate input
            uint256 collateralApy = apyOracle.getAPY(i);

            uint256 borrowRate = _calculateBorrowRate(
                collateralApy,
                ilkData.minimumProfitMargin,
                ilkData.optimalUtilizationRate,
                totalDebts[i], // WAD * RAY / WAD = RAY
                totalEthSupply,
                ilkData.distributionFactor
            );

            interestRates[i] = InterestRateData({ borrowRate: borrowRate, reserveFactor: ilkData.reserveFactor });

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }
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
        returns (InterestRateData memory)
    {
        IlkData memory ilkData = _unpackCollateralConfig(ilkIndex);

        // TODO: Validate input
        uint256 collateralApy = apyOracle.getAPY(ilkIndex);

        uint256 borrowRate = _calculateBorrowRate(
            collateralApy,
            ilkData.minimumProfitMargin,
            ilkData.optimalUtilizationRate,
            totalDebt,
            totalEthSupply,
            ilkData.distributionFactor
        );

        return InterestRateData({ borrowRate: borrowRate, reserveFactor: _scaleToRay(ilkData.reserveFactor, 18) });
    }

    /**
     *
     * @param collteralApy apy of the collateral (6 decimals)
     * @param minimumProfitMargin minimum profit margin (18 decimals)
     * @param optimalUtilizationRate kink of the curve (18 decimals)
     * @param totalDebt against the collateral (27 decimals)
     * @param totalEthSupply total eth supply of the system (18 decimals)
     * @param distributionFactor collateral specific borrow cap (2 decimals)
     * @return borrowRate borrow rate of the collateral (27 decimals)
     */
    function _calculateBorrowRate(
        uint256 collteralApy,
        uint80 minimumProfitMargin,
        uint64 optimalUtilizationRate,
        uint256 totalDebt,
        uint256 totalEthSupply,
        uint16 distributionFactor
    )
        internal
        pure
        returns (uint256 borrowRate)
    {
        // TODO: Above kink rate borrow rate
        uint256 distributionFactorRay = _scaleToRay(uint256(distributionFactor), 2);
        uint256 collateralApyRay = _scaleToRay(collteralApy, 6);
        uint256 minimumProfitMarginRay = _scaleToRay(uint256(minimumProfitMargin), 18);
        uint256 optimalUtilizationRateRay = _scaleToRay(optimalUtilizationRate, 18);
        totalEthSupply = _scaleToRay(totalEthSupply, 18);

        uint256 slope = (collateralApyRay - minimumProfitMarginRay).roundedRayDiv(optimalUtilizationRateRay);

        uint256 utilizationRate = totalDebt.roundedRayDiv(totalEthSupply.roundedRayMul(distributionFactorRay));

        borrowRate = utilizationRate.roundedRayMul(slope) + RAY;
    }

    function _scaleToRay(uint256 value, uint256 scale) internal pure returns (uint256) {
        return value * (10 ** 27) / (10 ** scale);
    }
}
