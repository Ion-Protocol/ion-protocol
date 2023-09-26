// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface ILidoWstETH {
    function stEthPerToken() external returns (uint256);
}

interface IStaderOracle {
    function exchangeRate() external returns (uint256 reportingBlockNumber, uint256 totalETHBalance, uint256 totalETHXSupply);
}

interface ISwellETH {
    function swETHToETHRate() external returns (uint256);
}