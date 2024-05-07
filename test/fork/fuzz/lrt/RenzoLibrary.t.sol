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

/**
 * Used for comparing different backcompute methods.
 */
library OldRenzoLibrary {
    error InvalidAmountOut(uint256 amountOut);
    error InvalidAmountIn(uint256 amountIn);

    function mockCalculateMintAmount(
        uint256 _currentValueInProtocol,
        uint256 _existingEzETHSupply,
        uint256 _newValueAdded
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
        uint256 totalSupply,
        uint256 amountOut
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
        console2.log("newEzEthSupply: ", newEzEthSupply);
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
        uint256 totalTVL,
        uint256 totalSupply,
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

        uint256 ethAmount = mockCalculateDepositAmount(totalTVL, totalSupply, minAmountOut - 1);
        console2.log("first calculated ethAmount: ", ethAmount);
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
        console2.log("second calculated ethAmountIn: ", ethAmountIn);
        // Very rarely, the `inflationPercentage` is less by one. So we try both.
        if (mockCalculateMintAmount(totalTVL, totalSupply, ethAmountIn) >= minAmountOut) {
            return (ethAmountIn, amountOut);
        }

        ++inflationPercentage;
        ethAmountIn = inflationPercentage.mulDiv(totalTVL, WAD - inflationPercentage, Math.Rounding.Ceil);

        newEzETHSupply = (totalSupply * WAD) / (WAD - inflationPercentage);
        amountOut = newEzETHSupply - totalSupply;

        if (mockCalculateMintAmount(totalTVL, totalSupply, ethAmountIn) >= minAmountOut) {
            return (ethAmountIn, amountOut);
        }

        revert InvalidAmountOut(ethAmountIn);
    }
}

contract RenzoLibraryHelper {
    /**
     * Copy of the private _calculateMintAmount function in RenzoLibrary.sol
     */
    function forwardCompute(
        uint256 _existingEzETHSupply,
        uint256 _currentValueInProtocol,
        uint256 ethAmountIn
    )
        internal
        pure
        returns (uint256 mintAmount)
    {
        uint256 inflationPercentage = SCALE_FACTOR * ethAmountIn / (_currentValueInProtocol + ethAmountIn);
        uint256 newEzETHSupply = (_existingEzETHSupply * SCALE_FACTOR) / (SCALE_FACTOR - inflationPercentage);
        mintAmount = newEzETHSupply - _existingEzETHSupply;
    }

    /**
     * Copy of the private _calculateDepositAmount function in RenzoLibrary.sol
     */
    function backCompute(
        uint256 _existingEzETHSupply,
        uint256 _currentValueInProtocol,
        uint256 mintAmount
    )
        internal
        pure
        returns (uint256)
    {
        if (mintAmount == 0) return 0;

        uint256 newEzETHSupply = mintAmount + _existingEzETHSupply;

        uint256 inflationPercentage = SCALE_FACTOR - ((SCALE_FACTOR * _existingEzETHSupply) / newEzETHSupply);

        uint256 ethAmountIn = inflationPercentage * _currentValueInProtocol / (SCALE_FACTOR - inflationPercentage);

        if (inflationPercentage * _currentValueInProtocol % (SCALE_FACTOR - inflationPercentage) != 0) {
            ethAmountIn++;
        }

        return ethAmountIn;
    }
}

contract RenzoLibrary_Comparison_FuzzTest is RenzoLibraryHelper, Test {
    function setUp() public { }

    /**
     * Compare which method has a lower dust bound.
     * Compare which method has a lower ethAmountIn.
     * Old method dust is always greater than the new method dust.
     * Out of 10000 runs,
     * - 9576 runs have equal ethAmountIn.
     * - 420 runs have old method ethAmountIn greater than new method ethAmountIn.
     * - 2 runs have old method ethAmountIn less than new method ethAmountIn.
     */
    function testFuzz_BackComputeComparison(
        uint256 _existingEzETHSupply,
        uint128 minMintAmount,
        uint256 exchangeRate
    )
        public
    {
        uint256 maxExistingEzETHSupply = 120_000_000e18;

        _existingEzETHSupply = bound(_existingEzETHSupply, 1e18, maxExistingEzETHSupply);

        exchangeRate = bound(exchangeRate, 1e18, 3e18);

        uint256 _currentValueInProtocol = _existingEzETHSupply * exchangeRate / 1e18; // backed 1:1

        minMintAmount = uint128(bound(uint256(minMintAmount), 1e9, _existingEzETHSupply));

        (uint256 oldMethodEthAmountIn, uint256 actualLrtAmount) = OldRenzoLibrary.mockGetEthAmountInForLstAmountOut(
            _currentValueInProtocol, _existingEzETHSupply, minMintAmount
        );

        uint256 newMethodEthAmountIn = backCompute(_existingEzETHSupply, _currentValueInProtocol, minMintAmount);

        uint256 oldMethodActualMintAmountOut =
            forwardCompute(_existingEzETHSupply, _currentValueInProtocol, oldMethodEthAmountIn);
        uint256 newMethodActualMintAmountOut =
            forwardCompute(_existingEzETHSupply, _currentValueInProtocol, newMethodEthAmountIn);

        vm.assume(oldMethodActualMintAmountOut != 0);
        vm.assume(newMethodActualMintAmountOut != 0);

        assertGe(
            oldMethodActualMintAmountOut,
            newMethodActualMintAmountOut,
            "old method mint amount out is greater than or equal to new method mint amount out"
        );

        assertApproxEqAbs(oldMethodEthAmountIn, newMethodEthAmountIn, 1e8, "eth amount in approx eq");

        uint256 oldMethodDust = oldMethodActualMintAmountOut - minMintAmount;
        uint256 newMethodDust = newMethodActualMintAmountOut - minMintAmount;

        assertGe(oldMethodDust, newMethodDust, "old method dust is greater than or equal to new method dust");
        assertLe(oldMethodDust - newMethodDust, 1e9, "dust differential bound");

        assertLe(newMethodDust, 1e9, "gwei bound"); // depends heavily on `maxExistingEzETHSupply`
    }
}

contract RenzoLibrary_FuzzTest is RenzoLibraryHelper, Test {
    /**
     * -- Observations ---
     * Max _existingEzETHSupply 10Me18 ($30B)
     * _currentValueInProtocol = _existingEzETHSupply
     * Max mintAmount _existingEzETHSupply / 2
     * New Method: 1.75e7 fail, 1e8 pass
     * Old Method: 1.75e7 fail, 1e8 pass
     *
     * Max _existingEzETHSupply 10Me19 (26 zeroes)
     * 1e8 fails, 1e9 passes (9 zeroes)
     *
     * Max _existingEzETHSupply 10Me20 (27 zeroes)
     * 1e9 fails, 1e10 passes (10 zeroes)
     *
     * Max _existingEzETHSupply 10Me21
     * 1e10 fails, 1e11 passes
     *
     * Max _existingEzETHSuppply 10Me27
     * 1e16 fails, 1e17 passes
     *
     * No proof, but max dust goes up 10x as the _existingEzETHSupply goes up 10x.
     *
     * Q: What happens when the Max _existingEzETHSupply increases?
     * A: With all else equal, the dust increases.
     *
     * Q: What happens when the minMintAmount relative to _existingEzETHSupply increases?
     * A: With all else equal, if there is no bound, or if the bound is 100x the existing supply, dust increases
     *
     * Q: What happens when the exchangeRate between ezETH and underlying increases?
     * A: Even with very large exchange rates such as 10e18, the dust bound is not affected.
     */
    function testFuzz_BackComputeDustBound(uint256 _existingEzETHSupply, uint128 minMintAmount) public {
        uint256 maxExistingEzETHSupply = 10_000_000e21;
        _existingEzETHSupply = bound(_existingEzETHSupply, 1, maxExistingEzETHSupply);

        uint256 _currentValueInProtocol = _existingEzETHSupply * 1.2e18 / 1e18; // backed 1.2:1

        minMintAmount = uint128(bound(uint256(minMintAmount), 0, _existingEzETHSupply / 2));

        uint256 ethAmountIn = backCompute(_currentValueInProtocol, _existingEzETHSupply, minMintAmount);
        uint256 actualMintAmountOut = forwardCompute(_currentValueInProtocol, _existingEzETHSupply, ethAmountIn);

        vm.assume(actualMintAmountOut != 0);
        assertGe(actualMintAmountOut, minMintAmount, "amount out comparison");

        assertLe(actualMintAmountOut - minMintAmount, 1e11, "gwei bound");
    }

    /**
     * _existingEzETHSupply / 10**17 bound passes with:
     * - _existingEzETHSupply [1e18, type(uint128).max]
     * - exchangeRate [1e18, 8e18]
     * - minMintAmount [0, _existingEzETHSupply]
     */
    function testFuzz_BackComputeFormulaicDustBound(
        uint256 _existingEzETHSupply,
        uint128 minMintAmount,
        uint128 exchangeRate
    )
        public
    {
        _existingEzETHSupply = bound(_existingEzETHSupply, WAD, type(uint128).max);

        exchangeRate = uint128(bound(exchangeRate, 1e18, 8e18)); // 9e18 fails

        uint256 _currentValueInProtocol = _existingEzETHSupply * exchangeRate / 1e18;

        minMintAmount = uint128(bound(uint256(minMintAmount), 0, _existingEzETHSupply));

        uint256 ethAmountIn = backCompute(_currentValueInProtocol, _existingEzETHSupply, minMintAmount);
        uint256 actualMintAmountOut = forwardCompute(_currentValueInProtocol, _existingEzETHSupply, ethAmountIn);

        uint256 dustBound = _existingEzETHSupply / 10 ** 17;

        vm.assume(actualMintAmountOut != 0);

        assertGe(actualMintAmountOut, minMintAmount, "amount out comparison");

        assertLe(actualMintAmountOut - minMintAmount, dustBound, "exact dust bound");
    }

    function testFuzz_BackComputeRealisticDustBound(
        uint256 _existingEzETHSupply,
        uint128 minMintAmount,
        uint128 exchangeRate
    )
        public
    {
        // There are 120M circulating ETH as of 4/9/2024.
        _existingEzETHSupply = bound(_existingEzETHSupply, WAD, 120_000_000e18);
        // realistically, the exchangeRate will not more than triple
        exchangeRate = uint128(bound(exchangeRate, 1e18, 3e18));
        // realistically, a single mint would not be double the entire supply
        minMintAmount = uint128(bound(uint256(minMintAmount), 0, _existingEzETHSupply * 2));

        uint256 _currentValueInProtocol = _existingEzETHSupply * exchangeRate / 1e18;

        uint256 ethAmountIn = backCompute(_currentValueInProtocol, _existingEzETHSupply, minMintAmount);
        uint256 actualMintAmountOut = forwardCompute(_currentValueInProtocol, _existingEzETHSupply, ethAmountIn);

        uint256 dustBound = 1e10;

        vm.assume(actualMintAmountOut != 0);

        assertGe(actualMintAmountOut, minMintAmount, "amount out comparison");
        assertLe(actualMintAmountOut - minMintAmount, dustBound, "exact dust bound");
    }

    function testFuzz_BackComputeResultIsOptimal(
        uint256 _existingEzETHSupply,
        uint128 minMintAmount,
        uint128 exchangeRate
    )
        public
    {
        uint256 maxExistingEzETHSupply = 10_000_000e18;

        _existingEzETHSupply = bound(_existingEzETHSupply, 1, maxExistingEzETHSupply);
        exchangeRate = uint128(bound(exchangeRate, 1e18, 2e18));
        minMintAmount = uint128(bound(uint256(minMintAmount), 0, _existingEzETHSupply));

        uint256 _currentValueInProtocol = _existingEzETHSupply * exchangeRate / 1e18;

        uint256 ethAmountIn = backCompute(_currentValueInProtocol, _existingEzETHSupply, minMintAmount);
        uint256 actualMintAmountOut = forwardCompute(_currentValueInProtocol, _existingEzETHSupply, ethAmountIn);

        vm.assume(ethAmountIn != 0);

        // try minting with one less
        uint256 mintAmountOutWithOneLess =
            forwardCompute(_currentValueInProtocol, _existingEzETHSupply, ethAmountIn - 1);

        assertLe(mintAmountOutWithOneLess, minMintAmount, "one less eth amount comopared to min mint amount");
        assertLe(mintAmountOutWithOneLess, actualMintAmountOut, "one less eth amount compared to actual mint amount");

        vm.assume(actualMintAmountOut != 0);
        assertGe(actualMintAmountOut, minMintAmount, "amount out comparison");

        assertLe(actualMintAmountOut - minMintAmount, 1e11, "gwei bound");
    }
}

contract RenzoLibrary_ForkFuzzTest is RenzoLibraryHelper, Test {
    function setUp() public {
        // vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19387902);
        vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"));
    }

    function test_GetEthAmountInForLstAmountOut() public {
        vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"), 19_472_376);
        uint128 minLrtAmount = 184_626_086_978_191_358;
        testForkFuzz_GetEthAmountInForLstAmountOut(minLrtAmount);
    }

    function test_GetLstAmountOutForEthAmountIn() public {
        vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"), 19_472_376);
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

    function testForkFuzz_GetEthAmountInForLstAmountOutWithDustBound(uint128 minLrtAmount) public {
        uint256 _existingEzETHSupply = EZETH.totalSupply();
        minLrtAmount = uint128(bound(uint256(minLrtAmount), 1, _existingEzETHSupply));

        (uint256 ethAmount, uint256 actualLrtAmount) = RenzoLibrary.getEthAmountInForLstAmountOut(minLrtAmount);
        assertGe(actualLrtAmount, minLrtAmount, "actualLrtAmount");

        uint256 mintAmount = _calculateMintAmount(ethAmount);
        vm.assume(mintAmount != 0);

        assertLe(mintAmount - minLrtAmount, 1e8, "hard coded dust bound");
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

    /**
     * The optimal amount outputted from this function should always be less
     * than the original input amount.
     */
    function testForkFuzz_GetLstAmountOutForEthAmountInOptimalAmount(uint128 ethAmount) public {
        (uint256 amount, uint256 optimalAmount) = RenzoLibrary.getLstAmountOutForEthAmountIn(ethAmount);
        assertLe(optimalAmount, ethAmount, "optimalAmount");
    }

    function _calculateMintAmount(uint256 ethAmount) internal view returns (uint256 mintAmount) {
        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();
        uint256 inflationPercentage = SCALE_FACTOR * ethAmount / (totalTVL + ethAmount);
        uint256 newEzETHSupply = (EZETH.totalSupply() * SCALE_FACTOR) / (SCALE_FACTOR - inflationPercentage);
        mintAmount = newEzETHSupply - EZETH.totalSupply();
    }
}
