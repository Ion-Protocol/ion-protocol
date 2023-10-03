// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IInterestRate {
    function getAllNewRates(uint256[] memory utilizationRates)
        external
        view
        returns (uint256 newSupplyFactor, uint256[] memory newIlkRates);

    function getNewRate(uint256 ilkIndex) external view returns (uint256 newSupplyFactor, uint256 newIlkRate);
}
