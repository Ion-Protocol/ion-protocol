// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ISwellDeposit } from "src/interfaces/DepositInterfaces.sol";
import { SwEthHandler } from "src/periphery/handlers/SwEthHandler.sol";
import { IonPool } from "src/IonPool.sol";
import { RoundedMath, WAD, RAY } from "src/libraries/math/RoundedMath.sol";
import {
    BalancerFlashloanDirectMintHandler,
    VAULT
} from "src/periphery/handlers/base/BalancerFlashloanDirectMintHandler.sol";
import { UniswapFlashswapHandler } from "src/periphery/handlers/base/UniswapFlashswapHandler.sol";
import { SwellLibrary } from "src/libraries/SwellLibrary.sol";

import { IonHandler_ForkBase } from "test/helpers/IonHandlerForkBase.sol";

import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";
import { IERC20 as IERC20Balancer } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { console2 } from "forge-std/console2.sol";

using RoundedMath for uint256;
using RoundedMath for uint104;
using SwellLibrary for ISwellDeposit;

contract SwEthHandler_ForkBase is IonHandler_ForkBase {

    uint8 internal constant ilkIndex = 2;
    SwEthHandler swEthHandler;
    uint160 sqrtPriceLimitX96;

    // TODO: Write test for increased `rate` value. Not much value to just check if `rate` is 1e27
    function setUp() public virtual override {
        super.setUp();
        swEthHandler = new SwEthHandler(ilkIndex, ionPool, ionRegistry, FACTORY, SWETH_ETH_POOL, 500);

        IERC20(address(MAINNET_SWELL)).approve(address(swEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        ISwellDeposit(MAINNET_SWELL).depositForLst(INITIAL_BORROWER_COLLATERAL_BALANCE);

        // If price of the pool ends up being larger than the exchange rate,
        // then a direct 1:1 contract mint is more favorable
        uint256 exchangeRate = MAINNET_SWELL.ethToSwETHRate();
        sqrtPriceLimitX96 = uint160(Math.sqrt(uint256(exchangeRate << 192) / 1e18));
    }
}

contract SwEthHandler_ForkTest is SwEthHandler_ForkBase {
    function testFork_FlashloanCollateral() public virtual {
        uint256 initialDeposit = 1e18; // in swEth
        uint256 resultingCollateral = 5e18; // in swEth
        uint256 resultingDebt = MAINNET_SWELL.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

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

    function testFork_FlashloanWeth() external {
        uint256 initialDeposit = 1e18; // in swEth
        uint256 resultingCollateral = 5e18; // in swEth
        uint256 resultingDebt = MAINNET_SWELL.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        uint256 gasBefore = gasleft();
        swEthHandler.flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertApproxEqAbs(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)),
            resultingDebt,
            1e27 / RAY
        );
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testFork_FlashswapLeverage() external {
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

    function testFork_FlashswapDeleverage() external {
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
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(ilkIndex, address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(ilkIndex));

        swEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0);

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated - normalizedDebtToRemove);
    }

    function testFork_RevertWhen_FlashloanNotInitiatedByHandler() external {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_SWELL));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalFlashloanNotAllowed.selector);
        VAULT.flashLoan(IFlashLoanRecipient(address(swEthHandler)), addresses, amounts, abi.encode(msg.sender, 0, 0, 0));
    }

    function testFork_RevertWhen_FlashloanedMoreThanOneToken() external {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](2);
        addresses[0] = IERC20Balancer(address(weth));
        addresses[1] = IERC20Balancer(address(MAINNET_SWELL));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 8e18;
        amounts[1] = 8e18;

        vm.expectRevert(abi.encodeWithSelector(BalancerFlashloanDirectMintHandler.FlashLoanedTooManyTokens.selector, 2));
        VAULT.flashLoan(IFlashLoanRecipient(address(swEthHandler)), addresses, amounts, abi.encode(msg.sender, 0, 0, 0));
    }

    function testFork_RevertWhen_UntrustedCallerCallsFlashloanCallback() external {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_SWELL));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        vm.expectRevert(
            abi.encodeWithSelector(BalancerFlashloanDirectMintHandler.ReceiveCallerNotVault.selector, address(this))
        );
        swEthHandler.receiveFlashLoan(addresses, amounts, amounts, "");
    }

    function testFork_RevertWhen_FlashloanedTokenIsNeitherWethNorCorrectLst() external {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_ETHX));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        // Should actually be impossible
        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalFlashloanNotAllowed.selector);
        vm.prank(address(VAULT));
        swEthHandler.receiveFlashLoan(addresses, amounts, amounts, abi.encode(address(this), 100e18, 100e18, 100e18));
    }

    function testFork_RevertWhen_UntrustedCallerCallsFlashswapCallback() external {
        vm.expectRevert(
            abi.encodeWithSelector(UniswapFlashswapHandler.CallbackOnlyCallableByPool.selector, address(this))
        );
        swEthHandler.uniswapV3SwapCallback(1, 1, "");
    }

    function testFork_RevertWhen_TradingInZeroLiquidityRegion() external {
        vm.prank(address(SWETH_ETH_POOL));
        vm.expectRevert(UniswapFlashswapHandler.InvalidZeroLiquidityRegionSwap.selector);
        swEthHandler.uniswapV3SwapCallback(0, 0, "");
    }

    function testFork_RevertWhen_FlashswapLeverageCreatesMoreDebtThanUserIsWilling() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = 3e18; // In weth

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        vm.expectRevert();
        swEthHandler.flashswapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);
    }

    function testFork_RevertWhen_FlashswapDeleverageSellsMoreCollateralThanUserIsWilling() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(swEthHandler), type(uint256).max);
        ionPool.addOperator(address(swEthHandler));

        swEthHandler.flashswapLeverage(initialDeposit, resultingCollateral, maxResultingDebt, sqrtPriceLimitX96);

        uint256 slippageAndFeeTolerance = 1.0e18; // 0%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(ilkIndex, address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(ilkIndex));

        vm.expectRevert();
        swEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0);
    }
}

contract SwEthHandler_WithRateChange_ForkTest is SwEthHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ilkIndex, 1.5708923502395e27);
    }
}
