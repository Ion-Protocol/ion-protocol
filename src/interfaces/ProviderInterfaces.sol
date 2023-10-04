// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface ILidoWstEth {
    function stEthPerToken() external view returns (uint256);
}

interface IStaderOracle {
    function exchangeRate()
        external
        view
        returns (uint256 reportingBlockNumber, uint256 totalETHBalance, uint256 totalETHXSupply);
}

interface ISwellEth {
    function swETHToETHRate() external view returns (uint256);
}
