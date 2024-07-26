// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";
import { WadRayMath, RAY, WAD } from "../../../../src/libraries/math/WadRayMath.sol";
import { AerodromeFlashswapHandler } from "../../../../src/flash/AerodromeFlashswapHandler.sol";
import { IonHandlerBase } from "../../../../src/flash/IonHandlerBase.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";
import { BASE_RSETH_WETH_AERODROME, BASE_RSETH, BASE_WETH } from "../../../../src/Constants.sol";
import { IPool } from "../../../../src/interfaces/aerodrome/IPool.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";
import { StdUtils } from "forge-std/Test.sol";

using WadRayMath for uint256;

interface IPoolFactory {
    function getFee(address pool, bool isStable) external view returns (uint256);
}

abstract contract AerodromeFlashswapHandler_Test is LrtHandler_ForkBase {

    function testFork_FlashswapLeverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = 6e18; // In weth

        console2.log("initial deposit: %d", initialDeposit);
        console2.log("resulting additional collateral: %d", resultingAdditionalCollateral);
        console2.log("max resulting debt: %d", maxResultingDebt);

        weth.approve(address(_getTypedUFHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFHandler()));

        vm.expectRevert(abi.encodeWithSelector(IonHandlerBase.TransactionDeadlineReached.selector, block.timestamp));
        _getTypedUFHandler().flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp,
            borrowerWhitelistProof
        );

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            _getTypedUFHandler().flashswapLeverage(
                initialDeposit,
                resultingAdditionalCollateral,
                maxResultingDebt,
                block.timestamp + 1,
                new bytes32[](0)
            );
        }

        uint256 gasBefore = gasleft();
        _getTypedUFHandler().flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp + 1,
            borrowerWhitelistProof
        );
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingAdditionalCollateral);
        // assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(_getTypedUFHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedUFHandler())), roundingError);
        assertLt(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt
        );
    }

    function testFork_FlashswapDeleverage() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(_getTypedUFHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFHandler()));

        vm.recordLogs();
        _getTypedUFHandler().flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
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

        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingAdditionalCollateral);
        assertLt(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt
        );
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), normalizedDebtCreated);

        vm.warp(block.timestamp + 3 hours);

        uint256 slippageAndFeeTolerance = 1.007e18; // 0.7%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingAdditionalCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(_getIlkIndex(), address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(_getIlkIndex()));

        vm.expectRevert(abi.encodeWithSelector(IonHandlerBase.TransactionDeadlineReached.selector, block.timestamp));
        _getTypedUFHandler().flashswapDeleverage(maxCollateralToRemove, debtToRemove, block.timestamp);

        _getTypedUFHandler().flashswapDeleverage(maxCollateralToRemove, debtToRemove, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertGe(
            ionPool.collateral(_getIlkIndex(), address(this)), resultingAdditionalCollateral - maxCollateralToRemove
        );
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), 0);
        // assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(_getTypedUFHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedUFHandler())), roundingError);
    }

    function testFork_FlashswapDeleverageFull() external {
        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(_getTypedUFHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFHandler()));

        vm.recordLogs();
        _getTypedUFHandler().flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
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

        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingAdditionalCollateral);
        assertLt(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt
        );
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), normalizedDebtCreated);

        uint256 slippageAndFeeTolerance = 1.007e18; // 0.7%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingAdditionalCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;

        // Remove all debt
        uint256 debtToRemove = type(uint256).max;

        _getTypedUFHandler().flashswapDeleverage(maxCollateralToRemove, debtToRemove, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        // assertGe(
        //     ionPool.collateral(_getIlkIndex(), address(this)), resultingAdditionalCollateral - maxCollateralToRemove
        // );
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), 0);
        // assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(_getTypedUFHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedUFHandler())), roundingError);
    }

    function testFork_RevertWhen_UntrustedCallerCallsFlashswapCallback() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        vm.expectRevert(
            abi.encodeWithSelector(AerodromeFlashswapHandler.CallbackOnlyCallableByPool.selector, address(this))
        );
        _getTypedUFHandler().hook(address(_getTypedUFHandler()), 1, 1, "");
    }

    function testFork_RevertWhen_TradingInZeroLiquidityRegion() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        vm.startPrank(address(BASE_RSETH_WETH_AERODROME));
        vm.expectRevert(AerodromeFlashswapHandler.InvalidZeroLiquidityRegionSwap.selector);
        _getTypedUFHandler().hook(address(_getTypedUFHandler()), 0, 0, "");
        vm.stopPrank();
    }

    function testFork_RevertWhen_FlashswapLeverageCreatesMoreDebtThanUserIsWilling() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = 3e18; // In weth

        weth.approve(address(_getTypedUFHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFHandler()));

        vm.expectRevert();
        _getTypedUFHandler().flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp + 1,
            new bytes32[](0)
        );
    }

    function testFork_RevertWhen_FlashswapDeleverageSellsMoreCollateralThanUserIsWilling() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = type(uint256).max;

        weth.approve(address(_getTypedUFHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFHandler()));

        _getTypedUFHandler().flashswapLeverage(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp + 1,
            new bytes32[](0)
        );

        uint256 slippageAndFeeTolerance = 1.0e18; // 0%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingAdditionalCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(_getIlkIndex(), address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(_getIlkIndex()));

        vm.expectRevert();
        _getTypedUFHandler().flashswapDeleverage(maxCollateralToRemove, debtToRemove, block.timestamp + 1);
    }

    function _getTypedUFHandler() private view returns (AerodromeFlashswapHandler) {
        return AerodromeFlashswapHandler(payable(_getHandler()));
    }
}
