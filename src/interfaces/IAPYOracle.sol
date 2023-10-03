// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IApyOracle {
    function apys(uint256 ilkIndex) external view returns (uint32);
}
