// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RoundedMath, WAD, RAY } from "../../src/libraries/math/RoundedMath.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SwEthHandler } from "../../src/periphery/handlers/SwEthHandler.sol";
import { IonPool } from "../../src/IonPool.sol";
import { IonHandler_ForkBase } from "../helpers/IonHandlerForkBase.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ISwellDeposit } from "../../src/interfaces/DepositInterfaces.sol";
import { Whitelist } from "src/Whitelist.sol";

import { Vm } from "forge-std/Vm.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { console2 } from "forge-std/console2.sol";

contract SwEthHandler_ForkBase is IonHandler_ForkBase {
    using RoundedMath for uint256;

    uint8 internal constant ilkIndex = 2;
    SwEthHandler swEthHandler;
    uint160 sqrtPriceLimitX96;

    // TODO: Write test for increased `rate` value. Not much value to just check if `rate` is 1e27
    function setUp() public virtual override {
        super.setUp();
        swEthHandler =
            new SwEthHandler(ilkIndex, ionPool, ionRegistry, Whitelist(whitelist), FACTORY, SWETH_ETH_POOL, 500);

        IERC20(address(MAINNET_SWELL)).approve(address(swEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        ISwellDeposit(MAINNET_SWELL).deposit{ value: INITIAL_BORROWER_COLLATERAL_BALANCE }();

        // If price of the pool ends up being larger than the exchange rate,
        // then a direct 1:1 contract mint is more favorable
        uint256 exchangeRate = ISwellDeposit(MAINNET_SWELL).ethToSwETHRate();
        sqrtPriceLimitX96 = uint160(Math.sqrt(uint256(exchangeRate << 192) / 1e18));
    }

    //TODO: Remove to SwellLibrary
    function _getLstAmountIn(uint256 amountLst) internal view returns (uint256) {
        return amountLst.wadDivUp(ISwellDeposit(MAINNET_SWELL).ethToSwETHRate());
    }
}

contract SwEthHandler_ForkTest is SwEthHandler_ForkBase {
    using RoundedMath for *;

    function testFork_swEthFlashLoanCollateral() public virtual {
        uint256 initialDeposit = 1e18; // in swEth
        uint256 resultingCollateral = 5e18; // in swEth
        uint256 resultingDebt = _getLstAmountIn(resultingCollateral - initialDeposit);

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        uint256 gasBefore = gasleft();
        swEthHandler.flashLeverageCollateral(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertGe(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)), resultingDebt);
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testFork_swEthFlashLoanWeth() external {
        uint256 initialDeposit = 1e18; // in swEth
        uint256 resultingCollateral = 5e18; // in swEth
        uint256 resultingDebt = _getLstAmountIn(resultingCollateral - initialDeposit);

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        uint256 gasBefore = gasleft();
        swEthHandler.flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertApproxEqAbs(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)), resultingDebt, 1e27 / RAY);
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testFork_swEthFlashSwapLeverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = 4.5e18; // In weth

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        uint256 gasBefore = gasleft();
        swEthHandler.flashswapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)) * ionPool.rate(ilkIndex), maxResultingDebt * RAY);
    }

    function testFork_swEthFlashSwapDeleverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

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
        uint256 debtToRemove = ionPool.normalizedDebt(ilkIndex, address(this)) * ionPool.rate(ilkIndex) / RAY;

        uint256 gasBefore = gasleft();
        swEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertGt(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        // This works because normalizedDebtCreated was done when `rate` was
        // 1e27, so it does not need to be converted to actual debt since it
        // will be same
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated - debtToRemove);
    }
}

contract SwEthHandler_ForkFuzzTest is SwEthHandler_ForkBase {
    using RoundedMath for *;

    /// forge-config: default.fuzz.runs = 100000
    function testForkFuzz_swEthFlashLoanCollateral(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        public
    {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = _getLstAmountIn(resultingCollateral - initialDeposit);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex);
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

    /// forge-config: default.fuzz.runs = 100000
    function testForkFuzz_swEthFlashLoanWeth(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = _getLstAmountIn(resultingCollateral - initialDeposit);

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
    /// forge-config: default.fuzz.runs = 100000
    function testForkFuzz_swEthFlashSwapLeverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        public
    {
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

    function testForkFuzz_swEthFlashSwapDeleverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        public
    {
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
        uint256 debtToRemove = normalizedDebtToRemove * ionPool.rate(ilkIndex) / RAY;

        swEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0);

        console.log(normalizedDebtCreated, debtToRemove);

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated - normalizedDebtToRemove);
    }
}

contract SwEthHandler_WithRateChange_ForkTest is SwEthHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        // Increase rate to 1e27
        ionPool.setRate(ilkIndex, 1.5708923502395e27);
    }
}

contract SwEthHandler_WithRateChange_ForkFuzzTest is SwEthHandler_ForkFuzzTest {
    /// forge-config: default.fuzz.runs = 100000
    function testForkFuzz_withRateChange_swEthFlashLoanCollateral(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_swEthFlashLoanCollateral(initialDeposit, resultingCollateralMultiplier);
    }

    /// forge-config: default.fuzz.runs = 10000
    function testForkFuzz_withRateChange_swEthFlashLoanWeth(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_swEthFlashLoanWeth(initialDeposit, resultingCollateralMultiplier);
    }

    /// forge-config: default.fuzz.runs = 100000
    function testForkFuzz_withRateChange_swEthFlashSwapLeverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_swEthFlashSwapLeverage(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_withRateChange_swEthFlashSwapDeleverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_swEthFlashSwapDeleverage(initialDeposit, resultingCollateralMultiplier);
    }
}
