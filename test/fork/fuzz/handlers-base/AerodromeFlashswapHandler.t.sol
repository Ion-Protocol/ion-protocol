// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";
import { WadRayMath, RAY, WAD } from "../../../../src/libraries/math/WadRayMath.sol";
import { AerodromeFlashswapHandler } from "../../../../src/flash/AerodromeFlashswapHandler.sol";
import { IonHandlerBase } from "../../../../src/flash/IonHandlerBase.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";
import { BASE_RSETH_WETH_AERODROME, BASE_RSETH, BASE_WETH } from "../../../../src/Constants.sol";
import { IPool } from "../../../../src/interfaces/IPool.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";
import { StdUtils } from "forge-std/Test.sol";

using WadRayMath for uint256;

interface IPoolFactory {
    function getFee(address pool, bool isStable) external view returns (uint256);
}

struct Config {
    uint256 initialDepositLowerBound;
}

abstract contract AerodromeFlashswapHandler_FuzzTest is LstHandler_ForkBase {
    uint160 sqrtPriceLimitX96;
    Config ufConfig;

     function testFuzz_amountOutGivenAmountIn(uint256 amountInToHandler, bool isLeverage) external{
        uint256 poolK = IPool(BASE_RSETH_WETH_AERODROME).getK();
        uint256 wethBalance = BASE_WETH.balanceOf(address(BASE_RSETH_WETH_AERODROME));
        uint256 lrtBalance = BASE_RSETH.balanceOf(address(BASE_RSETH_WETH_AERODROME));
        address factory = IPool(BASE_RSETH_WETH_AERODROME).factory();
        uint256 fee = IPoolFactory(factory).getFee(address(BASE_RSETH_WETH_AERODROME), false);
        uint256 maxValue = isLeverage ? lrtBalance : wethBalance;
        // skip 0 case since that would have returned already with no leverage or deleverage
        // also bound so that amount does not completely wipe out
        amountInToHandler = StdUtils.bound(amountInToHandler, 1, maxValue - 1);

        if(isLeverage){
            lrtBalance -= amountInToHandler;
        } else{
            wethBalance -= amountInToHandler;
        }
        uint256 amountOutFromUser = _getTypedUFHandler().getAmountOutGivenAmountIn(amountInToHandler, isLeverage);
        uint256 lowerAmountOutFromUser = amountOutFromUser - 1;
        uint256 wethLowerBound;
        uint256 lrtLowerBound;
        if(isLeverage){
            lrtLowerBound = lrtBalance;
            wethLowerBound = wethBalance + lowerAmountOutFromUser - (fee * lowerAmountOutFromUser)/10000;
            wethBalance += amountOutFromUser - (fee * amountOutFromUser)/10000;
            
        } else{
            wethLowerBound = wethBalance;
            lrtLowerBound = lrtBalance + lowerAmountOutFromUser - (fee * lowerAmountOutFromUser)/10000;
            lrtBalance += amountOutFromUser - (fee * amountOutFromUser)/10000;
        }

        uint256 newPoolK = wethBalance * lrtBalance;
        uint256 lowerBoundPoolK = wethLowerBound * lrtLowerBound;
        assertGe(newPoolK, poolK);
        assertGt(poolK, lowerBoundPoolK);
    }

    function testForkFuzz_FlashswapLeverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, ufConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(_getTypedUFHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFHandler()));

        _getTypedUFHandler().flashswapLeverage(
            initialDeposit,
            resultingCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral);
        assertEq(IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedUFHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedUFHandler())), roundingError);
        assertLt(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt
        );
    }

    function testForkFuzz_FlashswapDeleverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, ufConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(_getTypedUFHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFHandler()));

        vm.recordLogs();
        _getTypedUFHandler().flashswapLeverage(
            initialDeposit,
            resultingCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            new bytes32[](0)
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

        uint256 slippageAndFeeTolerance = 1.007e18; // 0.7%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        // Remove all debt
        uint256 normalizedDebtToRemove = ionPool.normalizedDebt(_getIlkIndex(), address(this));

        // Round up otherwise can leave 1 wei of dust in debt left
        uint256 debtToRemove = normalizedDebtToRemove.rayMulUp(ionPool.rate(_getIlkIndex()));

        _getTypedUFHandler().flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), 0);
        assertEq(IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedUFHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedUFHandler())), roundingError);
    }

    function testForkFuzz_FlashswapDeleverageFull(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        public
    {
        initialDeposit = bound(initialDeposit, ufConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(_getTypedUFHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFHandler()));

        vm.recordLogs();
        _getTypedUFHandler().flashswapLeverage(
            initialDeposit,
            resultingCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            new bytes32[](0)
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

        uint256 slippageAndFeeTolerance = 1.007e18; // 0.7%
        // Want to completely deleverage position and only leave initial capital
        // in vault
        uint256 maxCollateralToRemove = (resultingCollateral - initialDeposit) * slippageAndFeeTolerance / WAD;
        uint256 normalizedDebtCurrent = ionPool.normalizedDebt(_getIlkIndex(), address(this));

        // Remove all debt if any
        uint256 debtToRemove = normalizedDebtCurrent == 0 ? 0 : type(uint256).max;

        _getTypedUFHandler().flashswapDeleverage(maxCollateralToRemove, debtToRemove, 0, block.timestamp + 1);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertGe(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral - maxCollateralToRemove);
        assertEq(ionPool.normalizedDebt(_getIlkIndex(), address(this)), 0);
        assertEq(IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedUFHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedUFHandler())), roundingError);
    }

    function _getTypedUFHandler() private view returns (UniswapFlashswapHandler) {
        return UniswapFlashswapHandler(payable(_getHandler()));
    }
}

abstract contract AerodromeFlashswapHandler_WithRateChange_FuzzTest is AerodromeFlashswapHandler_FuzzTest {
    function testForkFuzz_WithRateChange_FlashswapLeverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_FlashswapLeverage(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_WithRateChange_FlashswapDeleverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_FlashswapDeleverage(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_WithRateChange_FlashswapDeleverageFull(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_FlashswapDeleverageFull(initialDeposit, resultingCollateralMultiplier);
    }
}