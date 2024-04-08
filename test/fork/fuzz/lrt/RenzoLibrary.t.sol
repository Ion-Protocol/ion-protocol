// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { WAD, RAY, WadRayMath } from "./../../../../src/libraries/math/WadRayMath.sol";
import { RenzoLibrary } from "../../../../src/libraries/lrt/RenzoLibrary.sol";
import { EZETH, RENZO_RESTAKE_MANAGER } from "../../../../src/Constants.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

using Math for uint256;
using WadRayMath for uint256;

uint256 constant SCALE_FACTOR = 1e18;

library MockRenzoLibrary {
    error InvalidAmountOut(uint256 amountOut);
    error InvalidAmountIn(uint256 amountIn);

    function mockCalculateMintAmount(
        uint256 _currentValueInProtocol,
        uint256 _newValueAdded,
        uint256 _existingEzETHSupply
    )
        public
        pure
        returns (uint256)
    {
        // For first mint, just return the new value added.
        // Checking both current value and existing supply to guard against gaming the initial mint
        if (_currentValueInProtocol == 0 || _existingEzETHSupply == 0) {
            return _newValueAdded; // value is priced in base units, so divide by scale factor
        }

        // Calculate the percentage of value after the deposit
        uint256 inflationPercentage = WAD * _newValueAdded / (_currentValueInProtocol + _newValueAdded);

        // Calculate the new supply
        uint256 newEzETHSupply = (_existingEzETHSupply * WAD) / (WAD - inflationPercentage);

        // Subtract the old supply from the new supply to get the amount to mint
        uint256 mintAmount = newEzETHSupply - _existingEzETHSupply;

        return mintAmount;
    }

    function mockCalculateDepositAmount(
        uint256 totalTVL,
        uint256 amountOut,
        uint256 totalSupply
    )
        public
        pure
        returns (uint256)
    {
        if (amountOut == 0) return 0;

        //        uint256 mintAmount = newEzETHSupply - _existingEzETHSupply;
        //
        // Solve for newEzETHSupply
        uint256 newEzEthSupply = (amountOut + totalSupply);
        uint256 newEzEthSupplyRay = newEzEthSupply.scaleUpToRay(18);

        //        uint256 newEzETHSupply = (_existingEzETHSupply * SCALE_FACTOR) / (SCALE_FACTOR -
        // inflationPercentage);
        //
        // Solve for inflationPercentage
        uint256 intem = totalSupply.scaleUpToRay(18).mulDiv(RAY, newEzEthSupplyRay);
        uint256 inflationPercentage = RAY - intem;

        //         uint256 inflationPercentage = SCALE_FACTOR * _newValueAdded / (_currentValueInProtocol +
        // _newValueAdded);
        //
        // Solve for _newValueAdded
        uint256 ethAmountRay = inflationPercentage.mulDiv(totalTVL.scaleUpToRay(18), RAY - inflationPercentage);

        // Truncate from RAY to WAD with roundingUp plus one extra
        // The one extra to get into the next mint range
        uint256 ethAmount = ethAmountRay / 1e9 + 1;
        if (ethAmountRay % 1e9 != 0) ++ethAmount;

        return ethAmount;
    }

    // current math but with configurable totalTVL and totalSupply
    function mockGetEthAmountInForLstAmountOut(
        uint256 totalSupply,
        uint256 totalTVL,
        uint256 minAmountOut
    )
        public
        view
        returns (uint256 ethAmountIn, uint256 amountOut)
    {
        if (minAmountOut == 0) return (0, 0);

        // passed in as params
        // (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();
        // uint256 totalSupply = EZETH.totalSupply();

        uint256 ethAmount = mockCalculateDepositAmount(totalTVL, minAmountOut - 1, totalSupply);

        if (ethAmount == 0) return (0, 0);
        uint256 inflationPercentage = WAD * ethAmount / (totalTVL + ethAmount);

        // Once we have the `inflationPercentage` mapping to the "mintable amount"
        // below `minAmountOut`, we increment it to find the
        // `inflationPercentage` mapping to the "mintable amount" above
        // `minAmountOut".
        ++inflationPercentage;

        // Then we go on to calculate the ezETH amount and optimal eth deposit
        // mapping to that `inflationPercentage`.

        // Calculate the new supply
        uint256 newEzETHSupply = (totalSupply * WAD) / (WAD - inflationPercentage);

        amountOut = newEzETHSupply - totalSupply;

        ethAmountIn = inflationPercentage.mulDiv(totalTVL, WAD - inflationPercentage, Math.Rounding.Ceil);

        // Very rarely, the `inflationPercentage` is less by one. So we try both.
        if (mockCalculateMintAmount(totalTVL, ethAmountIn, totalSupply) >= minAmountOut) {
            return (ethAmountIn, amountOut);
        }

        ++inflationPercentage;
        ethAmountIn = inflationPercentage.mulDiv(totalTVL, WAD - inflationPercentage, Math.Rounding.Ceil);

        newEzETHSupply = (totalSupply * WAD) / (WAD - inflationPercentage);
        amountOut = newEzETHSupply - totalSupply;

        if (mockCalculateMintAmount(totalTVL, ethAmountIn, totalSupply) >= minAmountOut) {
            return (ethAmountIn, amountOut);
        }

        revert InvalidAmountOut(ethAmountIn);
    }
}

contract RenzoLibrary_FuzzTest is Test {
    function setUp() public {
        // vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19387902);
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function forwardCompute(
        uint256 _existingEzETHSupply,
        uint256 _currentValueInProtocol,
        uint256 ethAmountIn
    )
        public
        pure
        returns (uint256 mintAmount)
    {
        uint256 inflationPercentage = SCALE_FACTOR * ethAmountIn / (_currentValueInProtocol + ethAmountIn);
        uint256 newEzETHSupply = (_existingEzETHSupply * SCALE_FACTOR) / (SCALE_FACTOR - inflationPercentage);
        mintAmount = newEzETHSupply - _existingEzETHSupply;
    }

    /// simpler back compute with default ethAmountIn++
    function backCompute(
        uint256 _existingEzETHSupply,
        uint256 _currentValueInProtocol,
        uint256 mintAmount
    )
        public
        pure
        returns (uint256)
    {
        if (mintAmount == 0) return 0;

        uint256 newEzETHSupply = mintAmount + _existingEzETHSupply;

        uint256 inflationPercentage = SCALE_FACTOR - ((SCALE_FACTOR * _existingEzETHSupply) / newEzETHSupply);

        uint256 ethAmountIn = inflationPercentage * _currentValueInProtocol / (SCALE_FACTOR - inflationPercentage);

        ethAmountIn++; // always increment by default

        return ethAmountIn;
    }

    // --- Observations ---
    // Max _existingEzETHSupply 10Me18 ($30B)
    // _currentValueInProtocol = _existingEzETHSupply
    // Max mintAmount _existingEzETHSupply / 2
    // New Method: 1.75e7 fail, 1e8 pass
    // Old Method: 1.75e7 fail, 1e8 pass

    // What happens when the Max _existingEzETHSupply increases?
    // With all else equal, the dust increases.

    // What happens when the minMintAmount relative to _existingEzETHSupply increases?
    // With all else equal, if there is no bound, or if the bound is 100x the existing supply, dust increases

    function testFuzz_NewMethodBackComputeDustBound(uint256 _existingEzETHSupply, uint128 minMintAmount) public {
        uint256 maxExistingEzETHSupply = 10_000_000e18;
        _existingEzETHSupply = bound(_existingEzETHSupply, 1, maxExistingEzETHSupply);

        uint256 _currentValueInProtocol = _existingEzETHSupply * 1.1e18 / 1e18; // backed 1:1

        minMintAmount = uint128(bound(uint256(minMintAmount), 0, _existingEzETHSupply / 2));

        uint256 ethAmountIn = backCompute(_existingEzETHSupply, _currentValueInProtocol, minMintAmount);
        uint256 actualMintAmountOut = forwardCompute(_existingEzETHSupply, _currentValueInProtocol, ethAmountIn);

        vm.assume(actualMintAmountOut != 0);
        assertGe(actualMintAmountOut, minMintAmount, "amount out comparison");

        assertLe(actualMintAmountOut - minMintAmount, 1e9, "gwei bound");
    }

    function testFuzz_OldMethodBackComputeDustBound(uint256 _existingEzETHSupply, uint128 minMintAmount) public {
        uint256 maxExistingEzETHSupply = 10_000_000e18;

        _existingEzETHSupply = bound(_existingEzETHSupply, 1, maxExistingEzETHSupply);

        uint256 _currentValueInProtocol = _existingEzETHSupply * 1.1e18 / 1e18; // backed 1:1

        minMintAmount = uint128(bound(uint256(minMintAmount), 0, _existingEzETHSupply / 2));

        (uint256 ethAmountIn, uint256 actualLrtAmount) = MockRenzoLibrary.mockGetEthAmountInForLstAmountOut(
            _existingEzETHSupply, _currentValueInProtocol, minMintAmount
        );
        uint256 actualMintAmountOut = forwardCompute(_existingEzETHSupply, _currentValueInProtocol, ethAmountIn);

        vm.assume(actualMintAmountOut != 0);
        assertGe(actualMintAmountOut, minMintAmount, "amount out comparison");

        assertLe(actualMintAmountOut - minMintAmount, 1e9, "gwei bound");
    }

    // --- Observations ---
    // oldMethodDust is always greater than newMethodDust

    function testFuzz_DustBoundComparison(uint256 _existingEzETHSupply, uint128 minMintAmount) public {
        uint256 maxExistingEzETHSupply = 10_000_000e18;

        _existingEzETHSupply = bound(_existingEzETHSupply, 1, maxExistingEzETHSupply);

        uint256 _currentValueInProtocol = _existingEzETHSupply * 1.1e18 / 1e18; // backed 1:1

        minMintAmount = uint128(bound(uint256(minMintAmount), 0, _existingEzETHSupply));

        (uint256 oldMethodEthAmountIn, uint256 actualLrtAmount) = MockRenzoLibrary.mockGetEthAmountInForLstAmountOut(
            _existingEzETHSupply, _currentValueInProtocol, minMintAmount
        );
        uint256 newMethodEthAmountIn = backCompute(_existingEzETHSupply, _currentValueInProtocol, minMintAmount);

        uint256 oldMethodActualMintAmountOut =
            forwardCompute(_existingEzETHSupply, _currentValueInProtocol, oldMethodEthAmountIn);
        uint256 newMethodActualMintAmountOut =
            forwardCompute(_existingEzETHSupply, _currentValueInProtocol, newMethodEthAmountIn);

        vm.assume(oldMethodActualMintAmountOut != 0);
        vm.assume(newMethodActualMintAmountOut != 0);

        console2.log("oldMethodEthAmountIn: ", oldMethodEthAmountIn);
        console2.log("newMethodEthAmountIn: ", newMethodEthAmountIn);
        console2.log("oldMethodActualMintAmountOut: ", oldMethodActualMintAmountOut);
        console2.log("newMethodActualMintAmountOut: ", newMethodActualMintAmountOut);

        assertGe(
            oldMethodEthAmountIn, newMethodEthAmountIn, "old method eth amount in is always greater than or equal to"
        );
        assertGe(
            oldMethodActualMintAmountOut,
            newMethodActualMintAmountOut,
            "old method mint amount out is equal to new method mint amount out"
        );
        assertApproxEqAbs(oldMethodEthAmountIn, newMethodEthAmountIn, 1e9, "eth amount in approx eq");

        uint256 oldMethodDust = oldMethodActualMintAmountOut - minMintAmount;
        uint256 newMethodDust = newMethodActualMintAmountOut - minMintAmount;

        assertGe(oldMethodDust, newMethodDust, "old method dust is greater than or equal to new method dust");
        assertLe(oldMethodDust - newMethodDust, 1e9, "dust differential bound");

        assertLe(newMethodDust, 1e9, "gwei bound"); // depends heavily on `maxExistingEzETHSupply`
    }

    function testForkFuzz_SimpleGetEthAmountInForLstAmountOutBounded(uint128 minMintAmount) public {
        // back compute
        (,, uint256 _currentValueInProtocol) = RENZO_RESTAKE_MANAGER.calculateTVLs();
        uint256 _existingEzETHSupply = EZETH.totalSupply();

        // bound realistic mint amount with relation to existing ezETH supply
        minMintAmount = uint128(bound(uint256(minMintAmount), 1, _existingEzETHSupply));

        uint256 ethAmountIn = backCompute(_existingEzETHSupply, _currentValueInProtocol, minMintAmount);
        console2.log("back compute ethAmountIn: ", ethAmountIn);

        // forward compute simulation
        // amount out must be greater than or equal to expected min amount out
        uint256 actualMintAmountOut = _calculateMintAmount(ethAmountIn);
        console2.log("actualMintAmountOut: ", actualMintAmountOut);
        vm.assume(actualMintAmountOut != 0);

        assertGe(actualMintAmountOut, minMintAmount, "amount out comparison");

        assertLe(actualMintAmountOut - minMintAmount, 1e7, "bound");

        vm.deal(address(this), ethAmountIn);
        RenzoLibrary.depositForLrt(ethAmountIn);
        assertEq(EZETH.balanceOf(address(this)), actualMintAmountOut, "ezETH balance check");
    }

    function test_GetEthAmountInForLstAmountOut() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_472_376);
        uint128 minLrtAmount = 184_626_086_978_191_358;
        testForkFuzz_GetEthAmountInForLstAmountOut(minLrtAmount);
    }

    function test_GetLstAmountOutForEthAmountIn() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_472_376);
        uint128 ethAmount = 185_854_388_659_820_839;
        testForkFuzz_GetLstAmountOutForEthAmountIn(ethAmount);
    }

    function testForkFuzz_GetEthAmountInForLstAmountOut(uint128 minLrtAmount) public {
        (uint256 ethAmount, uint256 actualLrtAmount) = RenzoLibrary.getEthAmountInForLstAmountOut(minLrtAmount);
        assertGe(actualLrtAmount, minLrtAmount, "actualLrtAmount");

        uint256 mintAmount = _calculateMintAmount(ethAmount);

        vm.assume(mintAmount != 0);

        vm.deal(address(this), ethAmount);
        RenzoLibrary.depositForLrt(ethAmount);
        assertEq(EZETH.balanceOf(address(this)), actualLrtAmount, "ezETH balance");
    }

    function testForkFuzz_GetLstAmountOutForEthAmountIn(uint128 ethAmount) public {
        uint256 mintAmount = _calculateMintAmount(ethAmount);

        // Prevent revert
        vm.assume(mintAmount != 0);

        (uint256 lrtAmountOut, uint256 minEthIn) = RenzoLibrary.getLstAmountOutForEthAmountIn(ethAmount);

        assertEq(lrtAmountOut, mintAmount, "ethAmount");

        (lrtAmountOut,) = RenzoLibrary.getLstAmountOutForEthAmountIn(minEthIn);

        assertEq(lrtAmountOut, mintAmount, "minEthIn");

        vm.deal(address(this), ethAmount);
        RenzoLibrary.depositForLrt(ethAmount);
        assertEq(EZETH.balanceOf(address(this)), lrtAmountOut);
    }

    function _calculateMintAmount(uint256 ethAmount) internal view returns (uint256 mintAmount) {
        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();
        uint256 inflationPercentage = SCALE_FACTOR * ethAmount / (totalTVL + ethAmount);
        uint256 newEzETHSupply = (EZETH.totalSupply() * SCALE_FACTOR) / (SCALE_FACTOR - inflationPercentage);
        mintAmount = newEzETHSupply - EZETH.totalSupply();
    }
}
