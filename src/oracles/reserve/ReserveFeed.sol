// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ReserveFeed is Ownable2Step {
    mapping(uint8 ilkIndex => uint256 exchangeRate) public exchangeRates;

    constructor(address owner) Ownable(owner) { }

    function setExchangeRate(uint8 _ilkIndex, uint256 _exchangeRate) external onlyOwner {
        exchangeRates[_ilkIndex] = _exchangeRate;
    }

    function getExchangeRate(uint8 _ilkIndex) external view returns (uint256) {
        return exchangeRates[_ilkIndex];
    }
}
