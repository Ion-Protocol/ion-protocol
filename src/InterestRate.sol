// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IInterestRate } from "./interfaces/IInterestRate.sol";

struct IlkData {
    uint80 minimumProfitMargin;
    uint64 reserveFactor;
    uint64 optimalUtilizationRate;
}

// forgefmt: disable-start

//                                                      256         208              144             80                   0
//                                                       |   empty   |    opt_util    |  reserve_fac |  min_profit_margin |
//                                                       |           |                |              |                    |

// 2 ** 80 - 1
uint256 constant PROFIT_MARGIN_MASK =                   0x00000000000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFF; 
// (2 ** (80 + 64) - 1) - (2 ** 80 - 1)
uint256 constant RESERVE_FACTOR_MASK =                  0x0000000000000000000000000000FFFFFFFFFFFFFFFF00000000000000000000; 
// (2 ** (80 + 64 + 64) - 1) - (2 ** (80 + 64) - 1)
uint256 constant OPTIMAL_UTILIZATION_MASK =             0x000000000000FFFFFFFFFFFFFFFF000000000000000000000000000000000000;

// forgefmt: disable-end

uint8 constant PROFIT_MARGIN_SHIFT = 0;
uint8 constant RESERVE_FACTOR_SHIFT = 80;
uint8 constant OPTIMAL_UTILIZATION_SHIFT = 80 + 64;

contract InterestRate is IInterestRate {
    error CollateralIndexOutOfBounds();
    error InvalidUtilizationRatesLength(uint256 collateralCount, uint256 utilizationRatesLength);

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

    uint256 immutable collateralCount;

    constructor(IlkData[] memory ilkDataList) {
        collateralCount = ilkDataList.length;

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
        );
    }

    function _unpackCollateralConfig(uint256 config, uint256 index) internal view returns (IlkData memory ilkData) {
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

        uint80 minimumProfitMargin = uint80((config & PROFIT_MARGIN_MASK) >> PROFIT_MARGIN_SHIFT);
        uint64 reserveFactor = uint64((config & RESERVE_FACTOR_MASK) >> RESERVE_FACTOR_SHIFT);
        uint64 optimalUilization = uint64((config & OPTIMAL_UTILIZATION_MASK) >> OPTIMAL_UTILIZATION_SHIFT);

        ilkData = IlkData({
            minimumProfitMargin: minimumProfitMargin,
            reserveFactor: reserveFactor,
            optimalUtilizationRate: optimalUilization
        });
    }

    /**
     *
     * @param utilizationRates utilzation rates of each collateral in ray
     * @return newSupplyFactor
     * @return newIlkRates
     */
    function getAllNewRates(uint256[] memory utilizationRates)
        external
        view
        returns (uint256 newSupplyFactor, uint256[] memory newIlkRates)
    {
        if (utilizationRates.length != collateralCount) {
            revert InvalidUtilizationRatesLength(collateralCount, utilizationRates.length);
        }

        for (uint256 i = 0; i < collateralCount;) {
            IlkData memory ilkData = _unpackCollateralConfig(0, i);

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }
    }

    function getNewRate(uint256 ilkIndex) external view returns (uint256 newSupplyFactor, uint256 newIlkRate) {
        IlkData memory ilkData = _unpackCollateralConfig(0, ilkIndex);
    }

    function calculateBorrowRate(
        uint256 collteralApy,
        uint80 minimumProfitMargin,
        uint64
    )
        internal
        pure
        returns (uint256 borrowRate)
    {
        borrowRate = collteralApy - minimumProfitMargin;
    }
}
