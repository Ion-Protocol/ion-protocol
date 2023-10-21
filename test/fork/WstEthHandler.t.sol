// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandler_ForkBase } from "../helpers/IonHandlerForkBase.sol";
import { RoundedMath, WAD, RAY } from "../../src/libraries/math/RoundedMath.sol";
import { WstEthHandler } from "../../src/periphery/handlers/WstEthHandler.sol";
import { ILidoWStEthDeposit } from "../../src/interfaces/DepositInterfaces.sol";
import { LidoLibrary } from "../../src/libraries/LidoLibrary.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

contract WstEthHandler_ForkBase is IonHandler_ForkBase {
    uint8 internal constant ilkIndex = 0;
    IUniswapV3Pool internal constant WSTETH_ETH_UNISWAP_POOL =
        IUniswapV3Pool(0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa);

    WstEthHandler wstEthHandler;
    uint160 sqrtPriceLimitX96;

    function setUp() public override {
        super.setUp();
        wstEthHandler = new WstEthHandler(ilkIndex, ionPool, ionRegistry, FACTORY, WSTETH_ETH_UNISWAP_POOL, 100);

        IERC20(address(MAINNET_WSTETH)).approve(address(wstEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        (bool success,) = address(MAINNET_WSTETH).call{ value: INITIAL_BORROWER_COLLATERAL_BALANCE }("");
        require(success);

        // If price of the pool ends up being larger than the exchange rate,
        // then a direct 1:1 contract mint is more favorable
        uint256 exchangeRate = MAINNET_WSTETH.getStETHByWstETH(1 ether);
        sqrtPriceLimitX96 = uint160(Math.sqrt(uint256(exchangeRate << 192) / 1e18));
    }
}

contract WstEthHandler_ForkTest is WstEthHandler_ForkBase {
    using LidoLibrary for ILidoWStEthDeposit;

    function testFork_wstEthFlashLoanCollateral() external {
        uint256 initialDeposit = 1e18; // in wstEth
        uint256 resultingCollateral = 5e18; // in wstEth
        uint256 resultingDebt = MAINNET_WSTETH.getEthAmountInForLstAmount(resultingCollateral - initialDeposit);

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        uint256 gasBefore = gasleft();
        wstEthHandler.flashLeverageCollateral(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), resultingDebt);
    }

    function testFork_wstEthFlashLoanWeth() external {
        uint256 initialDeposit = 1e18; // in wstEth
        uint256 resultingCollateral = 5e18; // in wstEth
        uint256 resultingDebt = MAINNET_WSTETH.getEthAmountInForLstAmount(resultingCollateral - initialDeposit);

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        uint256 gasBefore = gasleft();
        wstEthHandler.flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), resultingDebt);
    }

    function testFork_wstEthFlashSwapLeverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = 4.9e18; // In weth

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        uint256 gasBefore = gasleft();
        wstEthHandler.flashSwapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)), maxResultingDebt);
    }

    function testFork_wstEthFlashSwapDeleverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        vm.recordLogs();
        wstEthHandler.flashSwapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);

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
        wstEthHandler.flashSwapDeleverage(maxCollateralToRemove, debtToRemove, 0);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertGt(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        // This works because normalizedDebtCreated was done when `rate` was
        // 1e27, so it does not need to be converted to actual debt since it
        // will be same
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated - debtToRemove);
    }
}

contract WstEthHandler_ForkFuzzTest is WstEthHandler_ForkBase {
    using LidoLibrary for ILidoWStEthDeposit;

    /// forge-config: default.fuzz.runs = 10000
    function testForkFuzz_wstEthFlashLoanCollateral(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        external
    {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = MAINNET_WSTETH.getEthAmountInForLstAmount(resultingCollateral - initialDeposit);

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        uint256 gasBefore = gasleft();
        wstEthHandler.flashLeverageCollateral(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), resultingDebt);
    }

    /// forge-config: default.fuzz.runs = 10000
    function testForkFuzz_wstEthFlashLoanWeth(uint256 initialDeposit, uint256 resultingCollateralMultiplier) external {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt = MAINNET_WSTETH.getEthAmountInForLstAmount(resultingCollateral - initialDeposit);

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        uint256 gasBefore = gasleft();
        wstEthHandler.flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), resultingDebt);
    }

    /// forge-config: default.fuzz.runs = 10000
    function testForkFuzz_wstEthFlashSwapLeverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        external
    {
        initialDeposit = bound(initialDeposit, 1e13, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        uint256 gasBefore = gasleft();
        wstEthHandler.flashSwapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        // Should be fine since rate is 1
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)), maxResultingDebt);
    }

    function testForkFuzz_wstEthFlashSwapDeleverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        vm.recordLogs();
        wstEthHandler.flashSwapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);

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
        wstEthHandler.flashSwapDeleverage(maxCollateralToRemove, debtToRemove, 0);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertGt(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        // This works because normalizedDebtCreated was done when `rate` was
        // 1e27, so it does not need to be converted to actual debt since it
        // will be same
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated - debtToRemove);
    }
}
