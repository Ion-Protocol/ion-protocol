// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

contract ReserveFeed {
    mapping(uint8 ilkIndex => uint256 exchangeRate) public exchangeRates;

    constructor() { }

    function setExchangeRate(uint8 _ilkIndex, uint256 _exchangeRate) external {
        exchangeRates[_ilkIndex] = _exchangeRate;
    }

    function getExchangeRate(uint8 _ilkIndex) external view returns (uint256) {
        return exchangeRates[_ilkIndex];
    }
}
