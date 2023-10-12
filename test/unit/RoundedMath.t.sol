// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { RoundedMath, RAY, WAD } from "../../src/math/RoundedMath.sol";

contract RoundedMath_Test is Test {
    function test_roundedWadMul() public {
        uint256 a = 7 * WAD;
        uint256 b = 8 * WAD;
        uint256 c = RoundedMath.roundedWadMul(a, b);
        assertEq(c, 56 * WAD);

        a = type(uint256).max;
        b = 2 * WAD;
        vm.expectRevert(abi.encodeWithSelector(RoundedMath.MultiplicationOverflow.selector, a, b));
        RoundedMath.roundedWadMul(a, b);
    }

    function test_roundedWadDiv() public {
        uint256 a = 56 * WAD;
        uint256 b = 4 * WAD;
        uint256 c = RoundedMath.roundedWadDiv(a, b);
        assertEq(c, 14 * WAD);

        a = type(uint256).max;
        b = 2 * WAD;
        vm.expectRevert(abi.encodeWithSelector(RoundedMath.MultiplicationOverflow.selector, a, b));
        RoundedMath.roundedWadMul(a, b);
        b = 0;
        vm.expectRevert(abi.encodeWithSelector(RoundedMath.DivisionByZero.selector));
        RoundedMath.roundedWadDiv(a, b);
    }

    function test_roundedRayMul() public {
        uint256 a = 7 * RAY;
        uint256 b = 8 * RAY;
        uint256 c = RoundedMath.roundedRayMul(a, b);
        assertEq(c, 56 * RAY);

        a = type(uint256).max;
        b = 2 * RAY;
        vm.expectRevert(abi.encodeWithSelector(RoundedMath.MultiplicationOverflow.selector, a, b));
        RoundedMath.roundedRayMul(a, b);
    }

    function test_roundedRayDiv() public {
        uint256 a = 56 * RAY;
        uint256 b = 4 * RAY;
        uint256 c = RoundedMath.roundedRayDiv(a, b);
        assertEq(c, 14 * RAY);

        a = type(uint256).max;
        b = 2 * RAY;
        vm.expectRevert(abi.encodeWithSelector(RoundedMath.MultiplicationOverflow.selector, a, b));
        RoundedMath.roundedRayMul(a, b);
        b = 0;
        vm.expectRevert(abi.encodeWithSelector(RoundedMath.DivisionByZero.selector));
        RoundedMath.roundedRayDiv(a, b);
    }
}
