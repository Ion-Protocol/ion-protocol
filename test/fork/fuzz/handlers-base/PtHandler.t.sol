// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WadRayMath, RAY } from "../../../../src/libraries/math/WadRayMath.sol";

import { PtHandler_ForkBase } from "../../../helpers/handlers/PtHandlerBase.sol";

import { PtQuoter } from "../../../helpers/PtQuoter.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

using WadRayMath for uint256;

abstract contract PtHandler_FuzzTest is PtHandler_ForkBase {
    PtQuoter ptQuoter;

    function testForkFuzz_PtLeverage(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        ptQuoter = new PtQuoter();

        initialDeposit = bound(initialDeposit, 0, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);

        uint256 collateralToFlashswap = resultingCollateral - initialDeposit;

        uint256 quote;

        if (collateralToFlashswap != 0) {
            quote = ptQuoter.quoteSyForExactPt(_getTypedPtHandler().MARKET(), collateralToFlashswap);
            // vm.assume(quote != 0);
        }

        uint256 additionalDebt = quote;
        uint256 ilkRate = ionPool.rate(_getIlkIndex());
        uint256 ilkSpot = ionPool.spot(_getIlkIndex()).getSpot();
        // Calculating this way emulates the newTotalDebt value in IonPool
        uint256 newTotalDebt = additionalDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        vm.assume(!unsafePositionChange);

        IERC20(_getUnderlying()).approve(_getHandler(), type(uint256).max);
        ionPool.addOperator(_getHandler());

        _getTypedPtHandler().ptLeverage(
            initialDeposit, resultingCollateral, additionalDebt, block.timestamp + 1, new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;
        if (currentRate % RAY != 0) ++roundingError;
    }
}

abstract contract PtHandler_WithRateChange_FuzzTest is PtHandler_FuzzTest {
    function testForkFuzz_WithRateChange_PtLeverage(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_PtLeverage(initialDeposit, resultingCollateralMultiplier);
    }
}
