// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library RoundedMath {
    error DivisionByZero();
    error MultiplicationOverflow();

    uint256 internal constant FULL_SCALE = 1e18;

    function roundedMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;

        if (a > (type(uint256).max / b)) revert MultiplicationOverflow();

        uint256 halfScale = FULL_SCALE / 2;

        return (a * b + halfScale) / FULL_SCALE;
    }

    function roundedDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) revert DivisionByZero();
        uint256 halfB = b / 2;

        if (a > (type(uint256).max - halfB) / FULL_SCALE) revert MultiplicationOverflow();

        return (a * FULL_SCALE + halfB) / b;
    }
}
