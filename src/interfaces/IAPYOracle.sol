// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IApyOracle {
    function getApy(uint256 ilkIndex) external view returns (uint256);
}
