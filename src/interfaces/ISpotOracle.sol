// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface ISpotOracle {
    error InvalidLtv(uint256 ltv);
    error InvalidReserveOracle();
    error MathOverflowedMulDiv();

    function LTV() external view returns (uint256);
    function RESERVE_ORACLE() external view returns (address);
    function getPrice() external view returns (uint256 price);
    function getSpot() external view returns (uint256 spot);
}
