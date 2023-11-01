// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface ILido {
    function totalSupply() external view returns (uint256);
    function getBufferedEther() external view returns (uint256);
    function getBeaconStat()
        external
        view
        returns (uint256 depositedValidators, uint256 beaconValidators, uint256 beaconBalance);
    function getTotalPooledEther() external view returns (uint256);
}

interface IWstEth {
    function stEthPerToken() external view returns (uint256);
}

interface IStaderOracle {
    function exchangeRate()
        external
        view
        returns (uint256 reportingBlockNumber, uint256 totalETHBalance, uint256 totalETHXSupply);
}

interface ISwEth {
    function swETHToETHRate() external view returns (uint256);
    function getRate() external view returns (uint256);
}
