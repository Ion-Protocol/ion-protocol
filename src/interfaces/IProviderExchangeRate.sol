// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface ILidoWstETH {
    function stEthPerToken() external;
}

interface IStaderOracle {
    function exchangeRate() external;
}

interface ISwellETH {
    function swETHToETHRate() external;
}