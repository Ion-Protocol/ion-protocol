// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

uint256 constant WAD = 1e18;
uint256 constant RAY = 1e27;
uint256 constant RAD = 1e45;

/**
 * @title WadRayMath
 * 
 * @notice This library provides mul/div[up/down] functionality for WAD, RAY and
 * RAD with phantom overflow protection as well as scale[up/down] functionality
 * for WAD, RAY and RAD.
 * 
 * @custom:security-contact security@molecularlabs.io
 */
library WadRayMath {
    using Math for uint256;
    
    error NotScalingUp(uint256 from, uint256 to);
    error NotScalingDown(uint256 from, uint256 to);

    /**
     * @notice Multiplies two WAD numbers and returns the result as a WAD
     * rounding the result down.
     * @param a Multiplicand.
     * @param b Multiplier.
     */
    function wadMulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, WAD);
    }

    /**
     * @notice Multiplies two WAD numbers and returns the result as a WAD
     * rounding the result up.
     * @param a Multiplicand.
     * @param b Multiplier.
     */
    function wadMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, WAD, Math.Rounding.Ceil);
    }

    /**
     * @notice Divides two WAD numbers and returns the result as a WAD rounding
     * the result down.
     * @param a Dividend.
     * @param b Divisor.
     */
    function wadDivDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(WAD, b);
    }

    /**
     * @notice Divides two WAD numbers and returns the result as a WAD rounding
     * the result up.
     * @param a Dividend.
     * @param b Divisor.
     */
    function wadDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(WAD, b, Math.Rounding.Ceil);
    }

    /**
     * @notice Multiplies two RAY numbers and returns the result as a RAY
     * rounding the result down.
     * @param a Multiplicand
     * @param b Multiplier
     */
    function rayMulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, RAY);
    }

    /**
     * @notice Multiplies two RAY numbers and returns the result as a RAY
     * rounding the result up.
     * @param a Multiplicand
     * @param b Multiplier
     */
    function rayMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, RAY, Math.Rounding.Ceil);
    }

    /**
     * @notice Divides two RAY numbers and returns the result as a RAY
     * rounding the result down.
     * @param a Dividend
     * @param b Divisor
     */
    function rayDivDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(RAY, b);
    }

    /**
     * @notice Divides two RAY numbers and returns the result as a RAY
     * rounding the result up.
     * @param a Dividend
     * @param b Divisor
     */
    function rayDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(RAY, b, Math.Rounding.Ceil);
    }

    /**
     * @notice Multiplies two RAD numbers and returns the result as a RAD
     * rounding the result down.
     * @param a Multiplicand
     * @param b Multiplier
     */
    function radMulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, RAD);
    }

    /**
     * @notice Multiplies two RAD numbers and returns the result as a RAD
     * rounding the result up.
     * @param a Multiplicand
     * @param b Multiplier
     */
    function radMulUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(b, RAD, Math.Rounding.Ceil);
    }

    /**
     * @notice Divides two RAD numbers and returns the result as a RAD rounding
     * the result down.
     * @param a Dividend
     * @param b Divisor
     */
    function radDivDown(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(RAD, b);
    }


    /**
     * @notice Divides two RAD numbers and returns the result as a RAD rounding
     * the result up.
     * @param a Dividend
     * @param b Divisor
     */
    function radDivUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return a.mulDiv(RAD, b, Math.Rounding.Ceil);
    }

    // --- Scalers ---

    /**
     * @notice Scales a value up from WAD. NOTE: The `scale` value must be
     * less than 18.
     * @param value to scale up.
     * @param scale of the returned value.
     */
    function scaleUpToWad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleUp(value, scale, 18);
    }


    /**
     * @notice Scales a value up from RAY. NOTE: The `scale` value must be
     * less than 27.
     * @param value to scale up.
     * @param scale of the returned value.
     */
    function scaleUpToRay(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleUp(value, scale, 27);
    }


    /**
     * @notice Scales a value up from RAD. NOTE: The `scale` value must be
     * less than 45.
     * @param value to scale up.
     * @param scale of the returned value.
     */
    function scaleUpToRad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleUp(value, scale, 45);
    }

    /**
     * @notice Scales a value down to WAD. NOTE: The `scale` value must be 
     * greater than 18. 
     * @param value to scale down.
     * @param scale of the returned value.
     */
    function scaleDownToWad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleDown(value, scale, 18);
    }

    /**
     * @notice Scales a value down to RAY. NOTE: The `scale` value must be 
     * greater than 27. 
     * @param value to scale down.
     * @param scale of the returned value.
     */
    function scaleDownToRay(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleDown(value, scale, 27);
    }


    /**
     * @notice Scales a value down to RAD. NOTE: The `scale` value must be 
     * greater than 45. 
     * @param value to scale down.
     * @param scale of the returned value.
     */
    function scaleDownToRad(uint256 value, uint256 scale) internal pure returns (uint256) {
        return scaleDown(value, scale, 45);
    }

    /**
     * @notice Scales a value up from one fixed-point precision to another. 
     * @param value to scale up.
     * @param from Precision to scale from.
     * @param to Precision to scale to.
     */
    function scaleUp(uint256 value, uint256 from, uint256 to) internal pure returns (uint256) {
        if (from >= to) revert NotScalingUp(from, to);
        return value * (10 ** (to - from));
    }

    /**
     * @notice Scales a value down from one fixed-point precision to another.
     * @param value to scale down.
     * @param from Precision to scale from.
     * @param to Precision to scale to.
     */
    function scaleDown(uint256 value, uint256 from, uint256 to) internal pure returns (uint256) {
        if (from <= to) revert NotScalingDown(from, to);
        return value / (10 ** (from - to));
    }
}
