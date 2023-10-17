// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IChainlink {
    function latestAnswer() external view returns (uint256 answer);
}