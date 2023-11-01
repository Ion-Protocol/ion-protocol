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
    error NotScalingUp(uint256 from, uint256 to);
    error NotScalingDown(uint256 from, uint256 to);

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

    function radMulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, RAD);
    }

    function radMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, RAD, Math.Rounding.Ceil);
    }

    function radDivDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(RAD, b);
    }

    function radDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(RAD, b, Math.Rounding.Ceil);
    }

    // --- Scalers ---

    function scaleUpToWad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleUp(value, scale, 18);
    }

    function scaleUpToRay(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleUp(value, scale, 27);
    }

    function scaleUpToRad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleUp(value, scale, 45);
    }

    function scaleDownToWad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleDown(value, scale, 18);
    }

    function scaleDownToRay(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleDown(value, scale, 27);
    }

    function scaleDownToRad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleDown(value, scale, 45);
    }

    function scaleUp(uint256 value, uint256 from, uint256 to) internal pure returns (uint256) {
        if (from >= to) revert NotScalingUp(from, to);
        return value * (10 ** (to - from));
    }

    function scaleDown(uint256 value, uint256 from, uint256 to) internal pure returns (uint256) {
        if (from <= to) revert NotScalingDown(from, to);
        return value / (10 ** (from - to));
    }
}
