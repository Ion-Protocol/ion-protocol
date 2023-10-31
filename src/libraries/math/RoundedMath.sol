// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

uint256 constant WAD = 1e18;
uint256 constant RAY = 1e27;
uint256 constant RAD = 1e45;

// TODO: Rename to WadRayMath and get rid of all `rounded...` functions
library RoundedMath {
    using Math for uint256;

    error MultiplicationOverflow(uint256 a, uint256 b);
    error DivisionByZero();

    /**
     * @dev Multiplication with proper rounding as opposed to truncation.
     * @param a multiplier
     * @param b multiplicand
     * @return product in `WAD`
     */
    function roundedWadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return roundedMul(a, b, WAD);
    }

    /**
     * @dev Division with proper rounding as opposed to truncation.
     * @param a dividend
     * @param b divisor
     * @return quotient in `WAD`
     */
    function roundedWadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return roundedDiv(a, b, WAD);
    }

    /**
     * @dev Multiplication with proper rounding as opposed to truncation.
     * @param a multiplier
     * @param b multiplicand
     * @return product in `RAY`
     */
    function roundedRayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return roundedMul(a, b, RAY);
    }

    /**
     * @dev Division with proper rounding as opposed to truncation.
     * @param a dividend
     * @param b divisor
     * @return quotient in `RAY`
     */
    function roundedRayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return roundedDiv(a, b, RAY);
    }

    /**
     * @dev Multiplication with proper rounding as opposed to truncation.
     * @param a multiplier
     * @param b multiplicand
     * @param scale of multiplicand
     * @return product (in scale of multiplier)
     */
    function roundedMul(uint256 a, uint256 b, uint256 scale) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;

        if (a > (type(uint256).max / b)) revert MultiplicationOverflow(a, b);

        uint256 halfScale = scale / 2;

        return (a * b + halfScale) / scale;
    }

    /**
     * @dev Division with proper rounding as opposed to truncation.
     * @param a dividend
     * @param b divisor
     * @param scale of divisor
     * @return quotient (in scale of dividend)
     */
    function roundedDiv(uint256 a, uint256 b, uint256 scale) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        uint256 halfB = b / 2;

        if (a > (type(uint256).max - halfB) / scale) revert MultiplicationOverflow(a, b);

        return (a * scale + halfB) / b;
    }

    function wadMulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, WAD);
    }

    function wadMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, WAD, Math.Rounding.Ceil);
    }

    function wadDivDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(WAD, b);
    }

    function wadDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(WAD, b, Math.Rounding.Ceil);
    }

    function rayMulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, RAY);
    }

    function rayMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, RAY, Math.Rounding.Ceil);
    }

    function rayDivDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(RAY, b);
    }

    function rayDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(RAY, b, Math.Rounding.Ceil);
    }

    // --- Scalers ---

    // TODO: use muldiv instead
    function scaleToWad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return value * (10 ** 18) / (10 ** scale);
    }

    function scaleToRay(uint256 value, uint256 scale) internal pure returns (uint256) {
        return value * (10 ** 27) / (10 ** scale);
    }

    function scaleToRad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return value * (10 ** 45) / (10 ** scale);
    }
}
