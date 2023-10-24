// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

// --- Exchange Rates ---

interface IWstEth {
    function stEthPerToken() external view returns (uint256);
}

interface ISwEth {
    function getRate() external view returns (uint256);
}

interface IStaderOracle {
    function exchangeRate()
        external
        view
        returns (uint256 reportingBlockNumber, uint256 totalETHBalance, uint256 totalETHXSupply);
}
