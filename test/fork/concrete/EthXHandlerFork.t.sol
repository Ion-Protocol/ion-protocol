// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IStaderStakePoolsManager } from "../../../src/interfaces/ProviderInterfaces.sol";
import { EthXHandler } from "../../../src/flash/handlers/EthXHandler.sol";
import { WadRayMath, WAD, RAY } from "../../../src/libraries/math/WadRayMath.sol";
import {
    BalancerFlashloanDirectMintHandler, VAULT
} from "../../../src/flash/handlers/base/BalancerFlashloanDirectMintHandler.sol";
import { UniswapFlashloanBalancerSwapHandler } from "../../../src/flash/handlers/base/UniswapFlashloanBalancerSwapHandler.sol";
import { StaderLibrary } from "../../../src/libraries/StaderLibrary.sol";
import { Whitelist } from "../../../src/Whitelist.sol";

import { IonHandler_ForkBase } from "../../helpers/IonHandlerForkBase.sol";

import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";
import { IERC20 as IERC20Balancer } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

using WadRayMath for uint256;
using WadRayMath for uint104;
using StaderLibrary for IStaderStakePoolsManager;

contract EthXHandler_ForkBase is IonHandler_ForkBase {
    uint8 internal constant ilkIndex = 1;
    EthXHandler ethXHandler;

    function setUp() public virtual override {
        super.setUp();
        ethXHandler =
        new EthXHandler(ilkIndex, ionPool, gemJoins[ilkIndex], MAINNET_STADER, Whitelist(whitelist), WSTETH_WETH_POOL);

        IERC20(address(MAINNET_ETHX)).approve(address(ethXHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        MAINNET_STADER.depositForLst(INITIAL_BORROWER_COLLATERAL_BALANCE);
    }
}

contract EthXHandler_ForkTest is EthXHandler_ForkBase {
    function testFork_FlashloanCollateral() public virtual {
        uint256 initialDeposit = 1e18; // in ethX
        uint256 resultingCollateral = 5e18; // in ethX
        uint256 resultingDebt = MAINNET_STADER.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        uint256 gasBefore = gasleft();
        ethXHandler.flashLeverageCollateral(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), resultingDebt);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(ethXHandler)), 0);
        assertLe(weth.balanceOf(address(ethXHandler)), roundingError);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testFork_FlashloanWeth() external {
        uint256 initialDeposit = 1e18; // in ethX
        uint256 resultingCollateral = 5e18; // in ethX
        uint256 resultingDebt = MAINNET_STADER.getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        uint256 gasBefore = gasleft();
        ethXHandler.flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertApproxEqAbs(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)),
            resultingDebt,
            1e27 / RAY
        );
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(ethXHandler)), 0);
        assertLe(weth.balanceOf(address(ethXHandler)), roundingError);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
    }

    function testFork_FlashswapLeverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = 4.5e18; // In weth

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        uint256 gasBefore = gasleft();
        ethXHandler.flashLeverageWethAndSwap(initialDeposit, resultingCollateral, maxResultingDebt);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingCollateral);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(ethXHandler)), 0);
        assertLe(weth.balanceOf(address(ethXHandler)), roundingError);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
    }

    function testFork_FlashswapDeleverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        vm.recordLogs();
        ethXHandler.flashLeverageWethAndSwap(initialDeposit, resultingCollateral, maxResultingDebt);

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

        uint256 gasBefore = gasleft();
        ethXHandler.flashDeleverageWethAndSwap(maxCollateralToRemove, debtToRemove);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), 0);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(ethXHandler)), 0);
        assertLe(weth.balanceOf(address(ethXHandler)), roundingError);
    }

    function testFork_RevertWhen_BalancerFlashloanNotInitiatedByHandler() external {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_ETHX));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalBalancerFlashloanNotAllowed.selector);
        VAULT.flashLoan(IFlashLoanRecipient(address(ethXHandler)), addresses, amounts, abi.encode(msg.sender, 0, 0, 0));
    }

    function testFork_RevertWhen_FlashloanedMoreThanOneToken() external {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](2);
        addresses[0] = IERC20Balancer(address(MAINNET_ETHX));
        addresses[1] = IERC20Balancer(address(weth));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 8e18;
        amounts[1] = 8e18;

        vm.expectRevert(abi.encodeWithSelector(BalancerFlashloanDirectMintHandler.FlashLoanedTooManyTokens.selector, 2));
        VAULT.flashLoan(IFlashLoanRecipient(address(ethXHandler)), addresses, amounts, abi.encode(msg.sender, 0, 0, 0));
    }

    function testFork_RevertWhen_UntrustedCallerCallsFlashloanCallback() external {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_ETHX));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        vm.expectRevert(
            abi.encodeWithSelector(BalancerFlashloanDirectMintHandler.ReceiveCallerNotVault.selector, address(this))
        );
        ethXHandler.receiveFlashLoan(addresses, amounts, amounts, "");
    }

    function testFork_RevertWhen_FlashloanedTokenIsNeitherWethNorCorrectLst() external {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_ETHX));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        // Should actually be impossible
        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalBalancerFlashloanNotAllowed.selector);
        vm.prank(address(VAULT));
        ethXHandler.receiveFlashLoan(addresses, amounts, amounts, abi.encode(address(this), 100e18, 100e18, 100e18));
    }

    function testFork_RevertWhen_UntrustedCallerCallsUniswapFlashloanCallback() external {
        vm.expectRevert(
            abi.encodeWithSelector(UniswapFlashloanBalancerSwapHandler.ReceiveCallerNotPool.selector, address(this))
        );
        ethXHandler.uniswapV3FlashCallback(1, 1, "");
    }

    function testFork_RevertWhen_FlashswapLeverageCreatesMoreDebtThanUserIsWilling() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = 3e18; // In weth

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        vm.expectRevert();
        ethXHandler.flashLeverageWethAndSwap(initialDeposit, resultingCollateral, maxResultingDebt);
    }

    function testFork_RevertWhen_FlashswapDeleverageSellsMoreCollateralThanUserIsWilling() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(ethXHandler), type(uint256).max);
        ionPool.addOperator(address(ethXHandler));

        ethXHandler.flashLeverageWethAndSwap(initialDeposit, resultingCollateral, maxResultingDebt);

        // No slippage tolerance
        uint256 slippageAndFeeTolerance = 1.0e18; // 0%
        uint256 maxCollateralToRemove = (resultingCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(ilkIndex, address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(ilkIndex));

        vm.expectRevert();
        ethXHandler.flashDeleverageWethAndSwap(maxCollateralToRemove, debtToRemove);
    }
}

contract EthXHandler_WithRateChange_ForkTest is EthXHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ilkIndex, 3.5708923502395e27);
    }
}
