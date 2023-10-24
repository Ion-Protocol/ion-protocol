// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SwEthHandler_ForkBase } from "test/fork/concrete/SwEthHandlerFork.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { RoundedMath, WAD, RAY } from "src/libraries/math/RoundedMath.sol";
import { ISwellDeposit } from "src/interfaces/DepositInterfaces.sol";
import { SwellLibrary } from "src/libraries/SwellLibrary.sol";

import { Vm } from "forge-std/Vm.sol";

using SwellLibrary for ISwellDeposit;

contract SwEthHandler_ForkFuzzTest is SwEthHandler_ForkBase {
    using RoundedMath for *;

    function testForkFuzz_FlashLoanCollateral(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = MAINNET_SWELL.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex);
        // Calculating this way emulates the newTotalDebt value in IonPool
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        vm.assume(!unsafePositionChange);

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        swEthHandler.flashLeverageCollateral(initialDeposit, resultingCollateral, resultingDebt);

        assertGe(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)), resultingDebt);
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testForkFuzz_FlashLoanWeth(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = MAINNET_SWELL.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex);
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        vm.assume(!unsafePositionChange);

        swEthHandler.flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt);

        assertApproxEqAbs(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)),
            resultingDebt,
            ilkRate / RAY
        );
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    // TODO: Replace all inlines with a deep fuzz config
    function testForkFuzz_FlashSwapLeverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 1e13, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        swEthHandler.flashswapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)) * ionPool.rate(ilkIndex), maxResultingDebt * RAY);
    }

    function testForkFuzz_FlashSwapDeleverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 1e13, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        vm.recordLogs();
        swEthHandler.flashswapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 normalizedDebtCreated;
        for (uint256 i = 0; i < entries.length; i++) {
            // keccak256("Borrow(uint8,address,address,uint256)")
            if (entries[i].topics[0] != 0x2849ef38636c2977383bd33bdb624c62112b78ba6e24b056290f50c02e029d8a) continue;
            normalizedDebtCreated = abi.decode(entries[i].data, (uint256));
        }

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)), maxResultingDebt);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated);

        uint256 slippageAndFeeTolerance = 1.005e18; // 0.5%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(ilkIndex, address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(ilkIndex));

        swEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0);

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated - normalizedDebtToRemove);
    }
}

contract SwEthHandler_WithRateChange_ForkFuzzTest is SwEthHandler_ForkFuzzTest {
    function testForkFuzz_withRateChange_FlashLoanCollateral(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_FlashLoanCollateral(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_withRateChange_FlashLoanWeth(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_FlashLoanWeth(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_withRateChange_FlashSwapLeverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_FlashSwapLeverage(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_withRateChange_FlashSwapDeleverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_FlashSwapDeleverage(initialDeposit, resultingCollateralMultiplier);
    }
}
