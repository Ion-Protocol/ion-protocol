// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WstEthHandler_ForkBase } from "test/fork/concrete/WstEthHandlerFork.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { WadRayMath, WAD, RAY } from "src/libraries/math/WadRayMath.sol";
import { IWstEth } from "src/interfaces/ProviderInterfaces.sol";
import { LidoLibrary } from "src/libraries/LidoLibrary.sol";

import { Vm } from "forge-std/Vm.sol";

using LidoLibrary for IWstEth;

abstract contract WstEthHandler_ForkFuzzTest is WstEthHandler_ForkBase {
    using WadRayMath for *;

    function testForkFuzz_FlashLoanCollateral(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex).getSpot();
        // Calculating this way emulates the newTotalDebt value in IonPool
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        vm.assume(!unsafePositionChange);

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        wstEthHandler.flashLeverageCollateral(initialDeposit, resultingCollateral, resultingDebt);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), resultingDebt);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testForkFuzz_FlashLoanWeth(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex).getSpot();
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        vm.assume(!unsafePositionChange);

        wstEthHandler.flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertApproxEqAbs(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)),
            resultingDebt,
            ilkRate / RAY
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testForkFuzz_FlashSwapLeverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 1e13, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        wstEthHandler.flashswapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
    }

    function testForkFuzz_FlashSwapDeleverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 1e13, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        vm.recordLogs();
        wstEthHandler.flashswapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 normalizedDebtCreated;
        for (uint256 i = 0; i < entries.length; i++) {
            // keccak256("Borrow(uint8,address,address,uint256,uint256,uint256)")
            if (entries[i].topics[0] != 0xe3e92e977f830d2a0b92c58e8866694b5dc929a35e2b95846f427de0f0bb412f) continue;
            normalizedDebtCreated = abi.decode(entries[i].data, (uint256));
        }

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated);

        vm.warp(block.timestamp + 3 hours);

        uint256 slippageAndFeeTolerance = 1.005e18; // 0.5%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(ilkIndex, address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(ilkIndex));

        wstEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), 0);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
    }
}

contract WstEthHandler_WithRateChange_ForkFuzzTest is WstEthHandler_ForkFuzzTest {
    function testForkFuzz_WithRateChange_FlashLoanCollateral(
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

    function testForkFuzz_WithRateChange_FlashLoanWeth(
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

    function testForkFuzz_WithRateChange_FlashSwapLeverage(
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

    function testForkFuzz_WithRateChange_FlashSwapDeleverage(
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
