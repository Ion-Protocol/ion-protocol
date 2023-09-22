// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

uint256 constant WAD = 1e18;
uint256 constant RAY = 1e27;

library RoundedMath {
    error DivisionByZero();
    error MultiplicationOverflow();

    /**
     * @dev Multiplication with proper rounding as opposed to truncation.
     * @param a multiplier
     * @param b multiplicand
     * @return product in `WAD`
     */
    function roundedWadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;

        if (a > (type(uint256).max / b)) revert MultiplicationOverflow();

        uint256 halfScale = WAD / 2;

        return (a * b + halfScale) / WAD;
    }

    /**
     * @dev Division with proper rounding as opposed to truncation.
     * @param a dividend
     * @param b divisor
     * @return quotient in `WAD`
     */
    function roundedWadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        uint256 halfB = b / 2;

        if (a > (type(uint256).max - halfB) / WAD) revert MultiplicationOverflow();

        return (a * WAD + halfB) / b;
    }

    /**
     * @dev Multiplication with proper rounding as opposed to truncation.
     * @param a multiplier
     * @param b multiplicand
     * @return product in `RAY`
     */
    function roundedRayMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;

        if (a > (type(uint256).max / b)) revert MultiplicationOverflow();

        uint256 halfScale = RAY / 2;

        return (a * b + halfScale) / RAY;
    }

    /**
     * @dev Division with proper rounding as opposed to truncation.
     * @param a dividend
     * @param b divisor
     * @return quotient in `RAY`
     */
    function roundedRayDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        uint256 halfB = b / 2;

        if (a > (type(uint256).max - halfB) / RAY) revert MultiplicationOverflow();

        return (a * RAY + halfB) / b;
    }
}
