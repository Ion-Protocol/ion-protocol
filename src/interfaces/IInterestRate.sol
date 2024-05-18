// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IInterestRate {
    struct IlkData {
        uint96 adjustedProfitMargin;
        uint96 minimumKinkRate;
        uint16 reserveFactor;
        uint96 adjustedBaseRate;
        uint96 minimumBaseRate;
        uint16 optimalUtilizationRate;
        uint16 distributionFactor;
        uint96 adjustedAboveKinkSlope;
        uint96 minimumAboveKinkSlope;
    }

    error CollateralIndexOutOfBounds();
    error DistributionFactorsDoNotSumToOne(uint256 sum);
    error InvalidIlkDataListLength(uint256 length);
    error InvalidMinimumKinkRate(uint256 minimumKinkRate, uint256 minimumBaseRate);
    error InvalidOptimalUtilizationRate(uint256 optimalUtilizationRate);
    error InvalidReserveFactor(uint256 reserveFactor);
    error InvalidYieldOracleAddress();
    error MathOverflowedMulDiv();
    error NotScalingUp(uint256 from, uint256 to);
    error TotalDebtsLength(uint256 COLLATERAL_COUNT, uint256 totalIlkDebtsLength);

    function COLLATERAL_COUNT() external view returns (uint256);
    function YIELD_ORACLE() external view returns (address);
    function calculateInterestRate(
        uint256 ilkIndex,
        uint256 totalIlkDebt,
        uint256 totalEthSupply
    )
        external
        view
        returns (uint256, uint256);
    function unpackCollateralConfig(uint256 index) external view returns (IlkData memory ilkData);
}
