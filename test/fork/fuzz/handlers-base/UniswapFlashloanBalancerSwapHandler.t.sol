// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandler_ForkBase } from "../../../helpers/IonHandlerForkBase.sol";
import { WadRayMath, RAY, WAD } from "../../../../src/libraries/math/WadRayMath.sol";
import { UniswapFlashloanBalancerSwapHandler } from
    "../../../../src/flash/handlers/base/UniswapFlashloanBalancerSwapHandler.sol";
import { IonHandlerBase } from "../../../../src/flash/handlers/base/IonHandlerBase.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

using WadRayMath for uint256;

struct Config {
    uint256 initialDepositLowerBound;
}

abstract contract UniswapFlashloanBalancerSwapHandler_FuzzTest is IonHandler_ForkBase {
    Config ufbsConfig;

    function testForkFuzz_flashLeverageWethAndSwap(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        public
    {
        initialDeposit = bound(initialDeposit, ufbsConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(_getTypedUFBSHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFBSHandler()));

        _getTypedUFBSHandler().flashLeverageWethAndSwap(
            initialDeposit, resultingCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(_getTypedUFBSHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedUFBSHandler())), roundingError);
        assertLt(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt
        );
    }

    function testForkFuzz_flashDeleverageWethAndSwap(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        public
    {
        initialDeposit = bound(initialDeposit, ufbsConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(_getTypedUFBSHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFBSHandler()));

        vm.recordLogs();
        _getTypedUFBSHandler().flashLeverageWethAndSwap(
            initialDeposit, resultingCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 normalizedDebtCreated;
        for (uint256 i = 0; i < entries.length; i++) {
            // keccak256("Borrow(uint8,address,address,uint256,uint256,uint256)")
            if (entries[i].topics[0] != 0xe3e92e977f830d2a0b92c58e8866694b5dc929a35e2b95846f427de0f0bb412f) continue;
            normalizedDebtCreated = abi.decode(entries[i].data, (uint256));
        }

        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral);
        assertLt(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt
        );
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), normalizedDebtCreated);

        vm.warp(block.timestamp + 3 hours);

        uint256 slippageAndFeeTolerance = 1.005e18; // 0.5%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(_getIlkIndex(), address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(_getIlkIndex()));

        _getTypedUFBSHandler().flashDeleverageWethAndSwap(maxCollateralToRemove, debtToRemove, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), 0);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(_getTypedUFBSHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedUFBSHandler())), roundingError);
    }

    function testForkFuzz_flashDeleverageWethAndSwapFull(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        public
    {
        initialDeposit = bound(initialDeposit, ufbsConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(_getTypedUFBSHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFBSHandler()));

        vm.recordLogs();
        _getTypedUFBSHandler().flashLeverageWethAndSwap(
            initialDeposit, resultingCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 normalizedDebtCreated;
        for (uint256 i = 0; i < entries.length; i++) {
            // keccak256("Borrow(uint8,address,address,uint256,uint256,uint256)")
            if (entries[i].topics[0] != 0xe3e92e977f830d2a0b92c58e8866694b5dc929a35e2b95846f427de0f0bb412f) continue;
            normalizedDebtCreated = abi.decode(entries[i].data, (uint256));
        }

        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral);
        assertLt(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt
        );
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), normalizedDebtCreated);

        vm.warp(block.timestamp + 3 hours);

        uint256 slippageAndFeeTolerance = 1.005e18; // 0.5%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 debtToRemove = type(uint256).max;

        _getTypedUFBSHandler().flashDeleverageWethAndSwap(maxCollateralToRemove, debtToRemove, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), 0);
        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(_getTypedUFBSHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedUFBSHandler())), roundingError);
    }

    function _getTypedUFBSHandler() internal view returns (UniswapFlashloanBalancerSwapHandler) {
        return UniswapFlashloanBalancerSwapHandler(payable(_getHandler()));
    }
}

abstract contract UniswapFlashloanBalancerSwapHandler_WithRateChange_FuzzTest is
    UniswapFlashloanBalancerSwapHandler_FuzzTest
{
    function testForkFuzz_WithRateChange_flashLeverageWethAndSwap(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_flashLeverageWethAndSwap(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_WithRateChange_flashDeleverageWethAndSwap(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_flashDeleverageWethAndSwap(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_WithRateChange_flashDeleverageWethAndSwapFull(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_flashDeleverageWethAndSwapFull(initialDeposit, resultingCollateralMultiplier);
    }
}
