// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WstEthHandler_ForkBase } from "../../../fork/concrete/lst/WstEthHandler.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { LstHandler_ForkBase } from "../../../helpers/handlers/LstHandlerForkBase.sol";
import { WadRayMath, RAY } from "../../../../src/libraries/math/WadRayMath.sol";
import { IWstEth } from "../../../../src/interfaces/ProviderInterfaces.sol";
import { LidoLibrary } from "../../../../src/libraries/lst/LidoLibrary.sol";
import {
    BalancerFlashloanDirectMintHandler_FuzzTest,
    BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest
} from "../handlers-base/BalancerFlashloanDirectMintHandler.t.sol";
import {
    UniswapFlashswapHandler_FuzzTest,
    UniswapFlashswapHandler_WithRateChange_FuzzTest
} from "../handlers-base/UniswapFlashswapHandler.t.sol";

using LidoLibrary for IWstEth;

abstract contract WstEthHandler_ForkFuzzTest is
    WstEthHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_FuzzTest,
    UniswapFlashswapHandler_FuzzTest
{
    function setUp() public virtual override(LstHandler_ForkBase, WstEthHandler_ForkBase) {
        super.setUp();
    }
}

contract WstEthHandler_ZapForkFuzzTest is WstEthHandler_ForkBase {
    using WadRayMath for *;

    function testForkFuzz_ZapDepositAndBorrow(uint256 depositAmount, uint256 borrowAmount) public {
        depositAmount = bound(depositAmount, 0.1 ether, INITIAL_THIS_UNDERLYING_BALANCE);
        borrowAmount = bound(borrowAmount, 0.1 ether, depositAmount);

        uint256 stEthDepositAmount = _mintStEth(depositAmount);
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex).getSpot();
        uint256 newTotalDebt = borrowAmount.rayDivDown(ilkRate) * ilkRate; // AmountToBorrow.IS_MAX for depositAndBorrow

        bool unsafePositionChange = newTotalDebt > wstEthDepositAmount * ilkSpot;

        vm.assume(!unsafePositionChange);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);
        ionPool.addOperator(address(wstEthHandler));

        wstEthHandler.zapDepositAndBorrow(stEthDepositAmount, borrowAmount, new bytes32[](0));

        uint256 currentRate = ionPool.rate(ilkIndex);
        // uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(ilkIndex, address(this)), wstEthDepositAmount, "collateral");
        assertLe(ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(currentRate), newTotalDebt / RAY + 1, "debt");
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "wstETH balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), 0, "weth dust");
    }

    function testForkFuzz_ZapFlashLoanCollateral(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier
    )
        public
    {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);

        uint256 initialStEthDeposit = _mintStEth(initialDeposit);
        uint256 resultingStEthDeposit = initialStEthDeposit * bound(resultingCollateralMultiplier, 1, 5);

        uint256 expectedInitialWstEthDeposit = MAINNET_WSTETH.getWstETHByStETH(initialStEthDeposit);
        uint256 expectedResultingWstEthDeposit = MAINNET_WSTETH.getWstETHByStETH(resultingStEthDeposit);

        uint256 resultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(expectedResultingWstEthDeposit - expectedInitialWstEthDeposit);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex).getSpot();
        // Calculating this way emulates the newTotalDebt value in IonPool
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > expectedResultingWstEthDeposit * ilkSpot;

        vm.assume(!unsafePositionChange);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), initialStEthDeposit);
        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        wstEthHandler.zapFlashLeverageCollateral(
            initialStEthDeposit, resultingStEthDeposit, resultingDebt, new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            resultingDebt + roundingError + 1,
            "max resulting debt bound"
        );
        assertEq(ionPool.collateral(ilkIndex, address(this)), expectedResultingWstEthDeposit, "collateral");
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "wstETH balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "weth dust");
    }

    function testForkFuzz_ZapFlashLoanWeth(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);

        uint256 initialStEthDeposit = _mintStEth(initialDeposit);
        uint256 resultingStEthDeposit = initialStEthDeposit * bound(resultingCollateralMultiplier, 1, 5);

        uint256 expectedInitialWstEthDeposit = IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(initialStEthDeposit);
        uint256 expectedResultingWstEthDeposit =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingStEthDeposit);

        uint256 resultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(expectedResultingWstEthDeposit - expectedInitialWstEthDeposit);

        uint256 ilkRate = ionPool.rate(ilkIndex);
        uint256 ilkSpot = ionPool.spot(ilkIndex).getSpot();
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > expectedResultingWstEthDeposit * ilkSpot;

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), initialStEthDeposit);
        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        vm.assume(!unsafePositionChange);

        wstEthHandler.zapFlashLeverageWeth(initialStEthDeposit, resultingStEthDeposit, resultingDebt, new bytes32[](0));

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertApproxEqAbs(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulDown(ionPool.rate(ilkIndex)),
            resultingDebt,
            ilkRate / RAY,
            "debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "wstETH balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "weth dust");
        assertEq(ionPool.collateral(ilkIndex, address(this)), expectedResultingWstEthDeposit, "collateral");
    }

    function testForkFuzz_ZapFlashSwapLeverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, 1e13, INITIAL_THIS_UNDERLYING_BALANCE);

        uint256 initialStEthDeposit = _mintStEth(initialDeposit);
        uint256 resultingStEthDeposit = initialStEthDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint160 sqrtPriceLimitX96 = 0;

        uint256 expectedResultingWstEthDeposit =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingStEthDeposit);

        uint256 maxResultingDebt = expectedResultingWstEthDeposit; // in weth. This is technically subject to slippage
            // but we will
            // skip protecting for this in the test

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), initialStEthDeposit);
        weth.approve(address(wstEthHandler), type(uint256).max);
        ionPool.addOperator(address(wstEthHandler));

        wstEthHandler.zapFlashswapLeverage(
            initialStEthDeposit,
            resultingStEthDeposit,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(ilkIndex, address(this)), expectedResultingWstEthDeposit, "collateral");
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "wstETH balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "weth dust");
        assertLt(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
    }
}

contract WstEthHandler_WithRateChange_ForkFuzzTest is
    WstEthHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest,
    UniswapFlashswapHandler_WithRateChange_FuzzTest
{
    function setUp() public virtual override(LstHandler_ForkBase, WstEthHandler_ForkBase) {
        super.setUp();
        ufConfig.initialDepositLowerBound = 1e13;
        bfdmConfig.initialDepositLowerBound = 4 wei;
    }
}

contract WstEthHandler_WithRateChange_ZapForkFuzzTest is WstEthHandler_ZapForkFuzzTest {
    function testForkFuzz_WithRateChange_ZapDepositAndBorrow(
        uint256 depositAmount,
        uint256 borrowAmount,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_ZapDepositAndBorrow(depositAmount, borrowAmount);
    }

    function testForkFuzz_WithRateChange_ZapFlashLoanCollateral(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_ZapFlashLoanCollateral(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_WithRateChange_FlashLoanWeth(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_ZapFlashLoanWeth(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_WithRateChange_FlashSwapLeverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(ilkIndex, rate);
        super.testForkFuzz_ZapFlashSwapLeverage(initialDeposit, resultingCollateralMultiplier);
    }
}
