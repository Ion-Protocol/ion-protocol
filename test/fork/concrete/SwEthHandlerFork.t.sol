// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ISwEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { SwEthHandler } from "../../../src/flash/handlers/SwEthHandler.sol";
import { WadRayMath, WAD, RAY } from "../../../src/libraries/math/WadRayMath.sol";
import {
    BalancerFlashloanDirectMintHandler, VAULT
} from "../../../src/flash/handlers/base/BalancerFlashloanDirectMintHandler.sol";
import { UniswapFlashswapHandler } from "../../../src/flash/handlers/base/UniswapFlashswapHandler.sol";
import { SwellLibrary } from "../../../src/libraries/SwellLibrary.sol";
import { Whitelist } from "../../../src/Whitelist.sol";

import { IonHandler_ForkBase } from "../../helpers/IonHandlerForkBase.sol";

import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";
import { IERC20 as IERC20Balancer } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

using WadRayMath for uint256;
using WadRayMath for uint104;
using SwellLibrary for ISwEth;

contract SwEthHandler_ForkBase is IonHandler_ForkBase {
    uint8 internal constant ilkIndex = 2;
    SwEthHandler swEthHandler;
    uint160 sqrtPriceLimitX96;

    function setUp() public virtual override {
        super.setUp();
        swEthHandler =
            new SwEthHandler(ilkIndex, ionPool, gemJoins[ilkIndex], Whitelist(whitelist), FACTORY, SWETH_ETH_POOL, 500);

        IERC20(address(MAINNET_SWELL)).approve(address(swEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        MAINNET_SWELL.depositForLst(INITIAL_BORROWER_COLLATERAL_BALANCE);

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

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), resultingDebt);
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertLe(weth.balanceOf(address(swEthHandler)), roundingError);
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

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertApproxEqAbs(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)),
            resultingDebt,
            roundingError
        );
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertLe(weth.balanceOf(address(swEthHandler)), roundingError);
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

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertLe(weth.balanceOf(address(swEthHandler)), roundingError);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
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
            // keccak256("Borrow(uint8,address,address,uint256,uint256,uint256)")
            if (entries[i].topics[0] != 0xe3e92e977f830d2a0b92c58e8866694b5dc929a35e2b95846f427de0f0bb412f) continue;
            normalizedDebtCreated = abi.decode(entries[i].data, (uint256));
        }

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
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

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), 0);
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(swEthHandler)), 0);
        assertLe(weth.balanceOf(address(swEthHandler)), roundingError);
    }

    function testFork_RevertWhen_FlashloanNotInitiatedByHandler() external {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_SWELL));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalBalancerFlashloanNotAllowed.selector);
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
        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalBalancerFlashloanNotAllowed.selector);
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

        ionPool.setRate(ilkIndex, 3.5708923502395e27);
    }
}
