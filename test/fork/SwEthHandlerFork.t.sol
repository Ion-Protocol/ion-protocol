// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RoundedMath, WAD, RAY } from "../../src/math/RoundedMath.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SwEthHandler } from "../../src/periphery/handlers/SwEthHandler.sol";
import { IonHandler_ForkBase } from "../helpers/IonHandlerForkBase.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ISwellDeposit } from "../../src/interfaces/DepositInterfaces.sol";

import { Vm } from "forge-std/Vm.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { console2 } from "forge-std/console2.sol";

contract SwEthHandler_ForkBase is IonHandler_ForkBase {
    using RoundedMath for uint256;

    uint8 internal constant ilkIndex = 2;
    SwEthHandler swEthHandler;
    uint160 sqrtPriceLimitX96;

    function setUp() public override {
        super.setUp();
        swEthHandler = new SwEthHandler(ilkIndex, ionPool, ionRegistry, FACTORY, SWETH_ETH_POOL);

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

    function _getLstAmountIn(uint256 amountLst) internal view returns (uint256) {
        return amountLst.wadDivUp(ISwellDeposit(MAINNET_SWELL).ethToSwETHRate());
    }
}

contract SwEthHandler_ForkTest is SwEthHandler_ForkBase {
    function testFork_swEthFlashLoanCollateral() external {
        uint256 initialDeposit = 1e18; // in swEth
        uint256 resultingCollateral = 5e18; // in swEth
        uint256 resultingDebt = _getLstAmountIn(resultingCollateral - initialDeposit);

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        uint256 gasBefore = gasleft();
        swEthHandler.flashLeverageCollateral(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), resultingDebt);
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

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), resultingDebt);
    }

    function testFork_swEthFlashSwapLeverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = 4.5e18;  // In weth

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        uint256 gasBefore = gasleft();
        swEthHandler.flashSwapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)), maxResultingDebt);
    }

    function testFork_swEthFlashSwapDeleverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        vm.recordLogs();
        swEthHandler.flashSwapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);

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
        swEthHandler.flashSwapDeleverage(maxCollateralToRemove, debtToRemove, 0);
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

    /// forge-config: default.fuzz.runs = 10000
    function testForkFuzz_swEthFlashLoanCollateral(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        external
    {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = _getLstAmountIn(resultingCollateral - initialDeposit);

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        uint256 gasBefore = gasleft();
        swEthHandler.flashLeverageCollateral(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), resultingDebt);
    }

    /// forge-config: default.fuzz.runs = 10000
    function testForkFuzz_swEthFlashLoanWeth(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    ) external {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = _getLstAmountIn(resultingCollateral - initialDeposit);

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        uint256 gasBefore = gasleft();
        swEthHandler.flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), resultingDebt);
    }

    function testForkFuzz_swEthFlashSwapLeverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    ) external {
        initialDeposit = bound(initialDeposit, 1e13, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will skip protecting for this in the test

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        uint256 gasBefore = gasleft();
        swEthHandler.flashSwapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)), maxResultingDebt);
    }

    function testForkFuzz_swEthFlashSwapDeleverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        vm.recordLogs();
        swEthHandler.flashSwapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);

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
        swEthHandler.flashSwapDeleverage(maxCollateralToRemove, debtToRemove, 0);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertGt(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        // This works because normalizedDebtCreated was done when `rate` was
        // 1e27, so it does not need to be converted to actual debt since it
        // will be same
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated - debtToRemove);
    }
}
