// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LstHandler_ForkBase } from "../../../helpers/handlers/LstHandlerForkBase.sol";
import { WadRayMath, RAY } from "../../../../src/libraries/math/WadRayMath.sol";
import { BalancerFlashloanDirectMintHandler } from "../../../../src/flash/BalancerFlashloanDirectMintHandler.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

using WadRayMath for uint256;

struct Config {
    uint256 initialDepositLowerBound;
}

abstract contract BalancerFlashloanDirectMintHandler_FuzzTest is LstHandler_ForkBase {
    Config bfdmConfig;

    function testForkFuzz_FlashLoanCollateral(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, bfdmConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt =
            _getProviderLibrary().getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        uint256 ilkRate = ionPool.rate(_getIlkIndex());
        uint256 ilkSpot = ionPool.spot(_getIlkIndex()).getSpot();
        // Calculating this way emulates the newTotalDebt value in IonPool
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        vm.assume(!unsafePositionChange);

        weth.approve(address(_getTypedBFDMHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedBFDMHandler()));

        _getTypedBFDMHandler().flashLeverageCollateral(
            initialDeposit, resultingCollateral, resultingDebt, new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertGe(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())), resultingDebt
        );
        assertEq(IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedBFDMHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedBFDMHandler())), roundingError);
        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral);
    }

    function testForkFuzz_FlashLoanWeth(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, bfdmConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 resultingDebt =
            _getProviderLibrary().getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);

        uint256 ilkRate = ionPool.rate(_getIlkIndex());
        uint256 ilkSpot = ionPool.spot(_getIlkIndex()).getSpot();
        uint256 newTotalDebt = resultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        weth.approve(address(_getTypedBFDMHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedBFDMHandler()));

        vm.assume(!unsafePositionChange);

        _getTypedBFDMHandler().flashLeverageWeth(initialDeposit, resultingCollateral, resultingDebt, new bytes32[](0));

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertApproxEqAbs(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulDown(ionPool.rate(_getIlkIndex())),
            resultingDebt,
            ilkRate / RAY
        );
        assertEq(IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedBFDMHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedBFDMHandler())), roundingError);
        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral);
    }

    function _getTypedBFDMHandler() private view returns (BalancerFlashloanDirectMintHandler) {
        return BalancerFlashloanDirectMintHandler(payable(_getHandler()));
    }
}

abstract contract BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest is
    BalancerFlashloanDirectMintHandler_FuzzTest
{
    function testForkFuzz_WithRateChange_FlashLoanCollateral(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_FlashLoanCollateral(initialDeposit, resultingCollateralMultiplier);
    }

    function testForkFuzz_WithRateChange_FlashLoanWeth(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_FlashLoanWeth(initialDeposit, resultingCollateralMultiplier);
    }
}
