// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWstEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { WstEthHandler } from "../../../src/flash/handlers/WstEthHandler.sol";
import { WadRayMath, WAD, RAY } from "../../../src/libraries/math/WadRayMath.sol";
import {
    BalancerFlashloanDirectMintHandler,
    VAULT
} from "../../../src/flash/handlers/base/BalancerFlashloanDirectMintHandler.sol";
import { UniswapFlashswapHandler } from "../../../src/flash/handlers/base/UniswapFlashswapHandler.sol";
import { LidoLibrary } from "../../../src/libraries/LidoLibrary.sol";
import { Whitelist } from "../../../src/Whitelist.sol";
import { IonHandlerBase } from "../../../src/flash/handlers/base/IonHandlerBase.sol";

import { IonHandler_ForkBase } from "../../helpers/IonHandlerForkBase.sol";

import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";
import { IERC20 as IERC20Balancer } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

using WadRayMath for uint256;
using WadRayMath for uint104;
using LidoLibrary for IWstEth;

contract WstEthHandler_ForkBase is IonHandler_ForkBase {
    uint8 internal constant ilkIndex = 0;
    WstEthHandler wstEthHandler;
    uint160 sqrtPriceLimitX96;
    bytes32[] borrowerWhitelistProof;

    function setUp() public virtual override {
        super.setUp();

        wstEthHandler = new WstEthHandler(ilkIndex, ionPool, gemJoins[ilkIndex], Whitelist(whitelist), WSTETH_WETH_POOL);

        IERC20(address(MAINNET_WSTETH)).approve(address(wstEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        MAINNET_WSTETH.depositForLst(INITIAL_BORROWER_COLLATERAL_BALANCE);

        // If price of the pool ends up being larger than the exchange rate,
        // then a direct 1:1 contract mint is more favorable
        uint256 exchangeRate = MAINNET_WSTETH.getStETHByWstETH(1 ether);
        sqrtPriceLimitX96 = uint160(Math.sqrt(uint256(exchangeRate << 192) / 1e18));
    }

    function _mintStEth(uint256 amount) internal returns (uint256) {
        uint256 beginningBalance = IERC20(address(MAINNET_STETH)).balanceOf(address(this));
        vm.deal(address(this), amount);
        (bool sent,) = address(MAINNET_STETH).call{ value: amount }("");
        require(sent == true, "mint stEth failed");
        uint256 resultingBalance = IERC20(address(MAINNET_STETH)).balanceOf(address(this));
        return resultingBalance - beginningBalance;
    }
}

contract WstEthHandler_ForkTest is WstEthHandler_ForkBase {
    function testFork_FlashloanCollateral() public virtual {
        uint256 initialDeposit = 1e18; // in wstEth
        uint256 resultingAdditionalCollateral = 5e18; // in wstEth
        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.flashLeverageCollateral(
                initialDeposit, resultingAdditionalCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        uint256 gasBefore = gasleft();
        wstEthHandler.flashLeverageCollateral(
            initialDeposit, resultingAdditionalCollateral, maxResultingDebt, borrowerWhitelistProof
        );
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalCollateral);
    }

    function testFork_FlashloanCollateralPositionRequiresZeroDebtButMaxAllowsMore() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        uint256 initialDeposit = 1e18; // in wstEth
        uint256 resultingAdditionalCollateral = 1e18 + 1; // in wstEth
        uint256 resultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.flashLeverageCollateral(
                initialDeposit, resultingAdditionalCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        uint256 gasBefore = gasleft();
        wstEthHandler.flashLeverageCollateral(
            initialDeposit, resultingAdditionalCollateral, maxResultingDebt, borrowerWhitelistProof
        );
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), resultingDebt);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalCollateral);
    }

    function testFork_FlashloanWeth() external {
        uint256 initialDeposit = 1e18; // in wstEth
        uint256 resultingAdditionalCollateral = 5e18; // in wstEth
        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.flashLeverageWeth(
                initialDeposit, resultingAdditionalCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        uint256 gasBefore = gasleft();
        wstEthHandler.flashLeverageWeth(
            initialDeposit, resultingAdditionalCollateral, maxResultingDebt, borrowerWhitelistProof
        );
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertApproxEqAbs(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            roundingError
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalCollateral);
    }

    function testFork_FlashswapLeverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = 4.9e18; // In weth

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.flashswapLeverage(
                initialDeposit,
                resultingAdditionalCollateral,
                maxResultingDebt,
                sqrtPriceLimitX96,
                block.timestamp + 1,
                new bytes32[](0)
            );
        }

        vm.expectRevert(abi.encodeWithSelector(IonHandlerBase.TransactionDeadlineReached.selector, block.timestamp));
        wstEthHandler.flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp,
            borrowerWhitelistProof
        );

        uint256 gasBefore = gasleft();
        wstEthHandler.flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            borrowerWhitelistProof
        );
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalCollateral);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
    }

    function testFork_FlashswapDeleverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        vm.recordLogs();
        wstEthHandler.flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            borrowerWhitelistProof
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 normalizedDebtCreated;
        for (uint256 i = 0; i < entries.length; i++) {
            // keccak256("Borrow(uint8,address,address,uint256,uint256,uint256)")
            if (entries[i].topics[0] != 0xe3e92e977f830d2a0b92c58e8866694b5dc929a35e2b95846f427de0f0bb412f) continue;
            normalizedDebtCreated = abi.decode(entries[i].data, (uint256));
        }

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalCollateral);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated);

        vm.warp(block.timestamp + 3 hours);

        uint256 slippageAndFeeTolerance = 1.005e18; // 0.5%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingAdditionalCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(ilkIndex, address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(ilkIndex));

        vm.expectRevert(abi.encodeWithSelector(IonHandlerBase.TransactionDeadlineReached.selector, block.timestamp));
        wstEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0, block.timestamp);

        wstEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), 0);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
    }

    function testFork_FlashswapDeleverageFull() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        vm.recordLogs();
        wstEthHandler.flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            borrowerWhitelistProof
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 normalizedDebtCreated;
        for (uint256 i = 0; i < entries.length; i++) {
            // keccak256("Borrow(uint8,address,address,uint256,uint256,uint256)")
            if (entries[i].topics[0] != 0xe3e92e977f830d2a0b92c58e8866694b5dc929a35e2b95846f427de0f0bb412f) continue;
            normalizedDebtCreated = abi.decode(entries[i].data, (uint256));
        }

        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalCollateral);
        assertLt(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)), maxResultingDebt);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), normalizedDebtCreated);

        uint256 slippageAndFeeTolerance = 1.005e18; // 0.5%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingAdditionalCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = type(uint256).max;

        wstEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), 0);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
    }

    function testFork_RevertWhen_FlashloanNotInitiatedByHandler() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_WSTETH));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalBalancerFlashloanNotAllowed.selector);
        VAULT.flashLoan(
            IFlashLoanRecipient(address(wstEthHandler)), addresses, amounts, abi.encode(msg.sender, 0, 0, 0)
        );
    }

    function testFork_RevertWhen_FlashloanedMoreThanOneToken() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        IERC20Balancer[] memory addresses = new IERC20Balancer[](2);
        addresses[0] = IERC20Balancer(address(MAINNET_WSTETH));
        addresses[1] = IERC20Balancer(address(weth));

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 8e18;
        amounts[1] = 8e18;

        vm.expectRevert(abi.encodeWithSelector(BalancerFlashloanDirectMintHandler.FlashLoanedTooManyTokens.selector, 2));
        VAULT.flashLoan(
            IFlashLoanRecipient(address(wstEthHandler)), addresses, amounts, abi.encode(msg.sender, 0, 0, 0)
        );
    }

    function testFork_RevertWhen_UntrustedCallerCallsFlashloanCallback() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_WSTETH));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        vm.expectRevert(
            abi.encodeWithSelector(BalancerFlashloanDirectMintHandler.ReceiveCallerNotVault.selector, address(this))
        );
        wstEthHandler.receiveFlashLoan(addresses, amounts, amounts, "");
    }

    function testFork_RevertWhen_FlashloanedTokenIsNeitherWethNorCorrectLst() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(MAINNET_ETHX));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        // Should actually be impossible
        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalBalancerFlashloanNotAllowed.selector);
        vm.prank(address(VAULT));
        wstEthHandler.receiveFlashLoan(addresses, amounts, amounts, abi.encode(address(this), 100e18, 100e18, 100e18));
    }

    function testFork_RevertWhen_UntrustedCallerCallsFlashswapCallback() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        vm.expectRevert(
            abi.encodeWithSelector(UniswapFlashswapHandler.CallbackOnlyCallableByPool.selector, address(this))
        );
        wstEthHandler.uniswapV3SwapCallback(1, 1, "");
    }

    function testFork_RevertWhen_TradingInZeroLiquidityRegion() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        vm.prank(address(WSTETH_WETH_POOL));
        vm.expectRevert(UniswapFlashswapHandler.InvalidZeroLiquidityRegionSwap.selector);
        wstEthHandler.uniswapV3SwapCallback(0, 0, "");
    }

    function testFork_RevertWhen_FlashswapLeverageCreatesMoreDebtThanUserIsWilling() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = 3e18; // In weth

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        vm.expectRevert();
        wstEthHandler.flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            borrowerWhitelistProof
        );
    }

    function testFork_RevertWhen_FlashswapDeleverageSellsMoreCollateralThanUserIsWilling() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        wstEthHandler.flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            borrowerWhitelistProof
        );

        uint256 slippageAndFeeTolerance = 1.0e18; // 0%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingAdditionalCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(ilkIndex, address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(ilkIndex));

        vm.expectRevert();
        wstEthHandler.flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0, block.timestamp + 1);
    }
}

contract WstEthHandler_Zap_ForkTest is WstEthHandler_ForkBase {
    function testFork_ZapDepositAndBorrow() external {
        uint256 ethDepositAmount = 2e18; // in eth
        uint256 borrowAmount = 0.5e18; // in weth

        uint256 stEthDepositAmount = _mintStEth(ethDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);
        ionPool.addOperator(address(wstEthHandler));

        // if whitelist root is not zero, check that incorrect merkle proof fails
        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapDepositAndBorrow(stEthDepositAmount, borrowAmount, new bytes32[](0));
        }

        wstEthHandler.zapDepositAndBorrow(stEthDepositAmount, borrowAmount, borrowerWhitelistProof);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        uint256 expectedWstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount); // in wstEth

        assertEq(ionPool.collateral(ilkIndex, address(this)), expectedWstEthDepositAmount);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), borrowAmount.rayDivUp(currentRate));
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
    }

    function testFork_ZapFlashLeverageCollateralZeroInitialDeposit() external {
        ionPool.addOperator(address(wstEthHandler));

        // first create a position
        uint256 ethDepositAndBorrowDepositAmount = 10e18;
        uint256 borrowAmount = 0e18;

        uint256 initialStEthDepositAmount = _mintStEth(ethDepositAndBorrowDepositAmount);
        uint256 startingWstEthDepositAmount =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(initialStEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), initialStEthDepositAmount);
        wstEthHandler.zapDepositAndBorrow(initialStEthDepositAmount, borrowAmount, borrowerWhitelistProof);

        // flash leverage inputs
        uint256 stEthDepositAmount = 0;
        uint256 resultingAdditionalStEthCollateral = 5e18;

        // expected inputs
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapFlashLeverageCollateral(
                stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        wstEthHandler.zapFlashLeverageCollateral(
            stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(
            ionPool.collateral(ilkIndex, address(this)),
            startingWstEthDepositAmount + resultingAdditionalWstEthCollateral,
            "collateral"
        );
        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "resulting debt lower than max resulting debt"
        );
        assertEq(
            IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)),
            0,
            "handler resulting wstEth balance is zero"
        );
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
    }

    function testFork_ZapFlashLeverageCollateral() external {
        uint256 ethDepositAmount = 2e18; // in eth

        // input to zap
        uint256 stEthDepositAmount = _mintStEth(ethDepositAmount);
        uint256 resultingAdditionalStEthCollateral = 5e18; // in stEth

        // expected input to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapFlashLeverageCollateral(
                stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        wstEthHandler.zapFlashLeverageCollateral(
            stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalWstEthCollateral, "collateral");
    }

    function testFork_ZapFlashLeverageWethZeroInitialDeposit() external {
        ionPool.addOperator(address(wstEthHandler));

        // first create a position
        uint256 ethDepositAndBorrowDepositAmount = 10e18;
        uint256 borrowAmount = 0e18;

        uint256 initialStEthDepositAmount = _mintStEth(ethDepositAndBorrowDepositAmount);
        uint256 startingWstEthDepositAmount =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(initialStEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), initialStEthDepositAmount);
        wstEthHandler.zapDepositAndBorrow(initialStEthDepositAmount, borrowAmount, borrowerWhitelistProof);

        // flash leverage with zero initial deposit param
        uint256 stEthDepositAmount = 0;
        uint256 resultingAdditionalStEthCollateral = 7e18; // in stEth

        // expected input to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);

        wstEthHandler.zapFlashLeverageWeth(
            stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(
            ionPool.collateral(ilkIndex, address(this)),
            startingWstEthDepositAmount + resultingAdditionalWstEthCollateral,
            "collateral"
        );
        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
    }

    function testFork_ZapFlashLeverageWeth() external {
        uint256 ethDepositAmount = 5e18; // in eth

        // input to zap
        uint256 stEthDepositAmount = _mintStEth(ethDepositAmount);
        uint256 resultingAdditionalStEthCollateral = 7e18; // in stEth

        // expected input to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapFlashLeverageWeth(
                stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        wstEthHandler.zapFlashLeverageWeth(
            stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalWstEthCollateral, "collateral");
    }

    function testFork_ZapFlashswapLeverageZeroInitialDeposit() external {
        ionPool.addOperator(address(wstEthHandler));

        // first create a position
        uint256 ethDepositAndBorrowDepositAmount = 10e18;
        uint256 borrowAmount = 0e18;

        uint256 initialStEthDepositAmount = _mintStEth(ethDepositAndBorrowDepositAmount);
        uint256 startingWstEthDepositAmount =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(initialStEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), initialStEthDepositAmount);
        wstEthHandler.zapDepositAndBorrow(initialStEthDepositAmount, borrowAmount, borrowerWhitelistProof);

        // flashswap with zero initial deposit param
        uint256 stEthDepositAmount = 0;
        uint256 resultingAdditionalStEthCollateral = 4.6e18;

        // expected inputs to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);
        uint160 sqrtPriceLimitX96 = 0;

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);

        vm.expectRevert(abi.encodeWithSelector(IonHandlerBase.TransactionDeadlineReached.selector, block.timestamp));
        wstEthHandler.zapFlashswapLeverage(
            stEthDepositAmount,
            resultingAdditionalStEthCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp,
            borrowerWhitelistProof
        );

        wstEthHandler.zapFlashswapLeverage(
            stEthDepositAmount,
            resultingAdditionalStEthCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(
            ionPool.collateral(ilkIndex, address(this)),
            startingWstEthDepositAmount + resultingAdditionalWstEthCollateral,
            "collateral"
        );
        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
    }

    function testFork_ZapFlashswapLeverage() external {
        uint256 ethDepositAmount = 1.4e18;

        // input to zap
        uint256 stEthDepositAmount = _mintStEth(ethDepositAmount);
        uint256 resultingAdditionalStEthCollateral = 2.8e18;

        // expected inputs to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);
        uint160 sqrtPriceLimitX96 = 0;

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapFlashswapLeverage(
                stEthDepositAmount,
                resultingAdditionalStEthCollateral,
                maxResultingDebt,
                sqrtPriceLimitX96,
                block.timestamp + 1,
                new bytes32[](0)
            );
        }

        vm.expectRevert(abi.encodeWithSelector(IonHandlerBase.TransactionDeadlineReached.selector, block.timestamp));
        wstEthHandler.zapFlashswapLeverage(
            stEthDepositAmount,
            resultingAdditionalStEthCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp,
            borrowerWhitelistProof
        );

        wstEthHandler.zapFlashswapLeverage(
            stEthDepositAmount,
            resultingAdditionalStEthCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalWstEthCollateral, "collateral");
    }
}

contract WstEthHandlerWhitelist_ForkTest is WstEthHandler_ForkTest, WstEthHandler_Zap_ForkTest {
    // generate merkle root
    // ["0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496"],
    // ["0x2222222222222222222222222222222222222222"],
    // => 0xb51a382d5bcb4cd5fe50a7d4d8abaf056ac1a6961cf654ec4f53a570ab75a30b

    bytes32 borrowerWhitelistRoot = 0x846dfddafc70174f2089edda6408bf9dd643c19ee06ff11643b614f0e277d6e3;

    bytes32[][] borrowerProofs = [
        [bytes32(0x708e7cb9a75ffb24191120fba1c3001faa9078147150c6f2747569edbadee751)],
        [bytes32(0xa6e6806303186f9c20e1af933c7efa83d98470acf93a10fb8da8b1d9c2873640)]
    ];

    function setUp() public override {
        super.setUp();

        bytes32[] memory borrowerRoots = new bytes32[](1);
        borrowerRoots[0] = borrowerWhitelistRoot;

        // update current whitelist with a new borrower root
        Whitelist _whitelist = Whitelist(ionPool.whitelist());
        _whitelist.updateBorrowersRoot(0, borrowerWhitelistRoot);
        _whitelist.approveProtocolWhitelist(address(wstEthHandler));

        borrowerWhitelistProof = borrowerProofs[0];
    }
}

contract WstEthHandler_WithRateChange_ForkTest is WstEthHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ilkIndex, 3.5708923502395e27);
    }
}
