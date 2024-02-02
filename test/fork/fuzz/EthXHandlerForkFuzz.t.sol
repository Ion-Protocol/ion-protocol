// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { EthXHandler_ForkBase } from "../../fork/concrete/EthXHandlerFork.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { WadRayMath, WAD, RAY } from "../../../src/libraries/math/WadRayMath.sol";
import { IStaderStakePoolsManager } from "../../../src/interfaces/ProviderInterfaces.sol";
import { StaderLibrary } from "../../../src/libraries/StaderLibrary.sol";

import { Vm } from "forge-std/Vm.sol";

using StaderLibrary for IStaderStakePoolsManager;

abstract contract EthXHandler_ForkFuzzTest is EthXHandler_ForkBase {
    using WadRayMath for *;

    uint256 minDeposit;
    uint256 maxDeposit;

    function setUp() public override {
        super.setUp();

        minDeposit = MAINNET_STADER.staderConfig().getMinDepositAmount();
        maxDeposit = MAINNET_STADER.staderConfig().getMaxDepositAmount();
    }

    function testForkFuzz_FlashLoanCollateral(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, minDeposit, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = MAINNET_STADER.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex).getSpot();
        // Calculating this way emulates the newTotalDebt value in IonPool
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        vm.assume(!unsafePositionChange);

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        ethXHandler.flashLeverageCollateral(initialDeposit, resultingCollateral, resultingDebt, new bytes32[](0));

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), resultingDebt);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(ethXHandler)), 0);
        assertLe(weth.balanceOf(address(ethXHandler)), roundingError);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testForkFuzz_FlashLoanWeth(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, minDeposit, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = MAINNET_STADER.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex).getSpot();
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        vm.assume(!unsafePositionChange);

        ethXHandler.flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt, new bytes32[](0));

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertApproxEqAbs(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)),
            resultingDebt,
            ilkRate / RAY
        );
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(ethXHandler)), 0);
        assertLe(weth.balanceOf(address(ethXHandler)), roundingError);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testForkFuzz_FlashSwapLeverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, minDeposit, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        ethXHandler.flashLeverageWethAndSwap(
            initialDeposit, resultingCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(ethXHandler)), 0);
        assertLe(weth.balanceOf(address(ethXHandler)), roundingError);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
    }

    function testForkFuzz_FlashSwapDeleverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, minDeposit, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        vm.recordLogs();
        ethXHandler.flashLeverageWethAndSwap(
            initialDeposit, resultingCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );

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

        ethXHandler.flashDeleverageWethAndSwap(maxCollateralToRemove, debtToRemove, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), 0);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(ethXHandler)), 0);
        assertLe(weth.balanceOf(address(ethXHandler)), roundingError);
    }

    function testForkFuzz_FlashSwapDeleverageFull(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        public
    {
        initialDeposit = bound(initialDeposit, minDeposit, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        vm.recordLogs();
        ethXHandler.flashLeverageWethAndSwap(
            initialDeposit, resultingCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );

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
        uint256 debtToRemove = type(uint256).max;

        ethXHandler.flashDeleverageWethAndSwap(maxCollateralToRemove, debtToRemove, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), 0);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(ethXHandler)), 0);
        assertLe(weth.balanceOf(address(ethXHandler)), roundingError);
    }
}

contract EthXHandler_WithRateChange_ForkFuzzTest is EthXHandler_ForkFuzzTest {
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
