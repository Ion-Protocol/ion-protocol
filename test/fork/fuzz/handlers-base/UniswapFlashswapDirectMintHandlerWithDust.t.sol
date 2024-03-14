// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";
import { UniswapFlashswapDirectMintHandlerWithDust } from
    "../../../../src/flash/UniswapFlashswapDirectMintHandlerWithDust.sol";
import { WadRayMath, RAY } from "../../../../src/libraries/math/WadRayMath.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

using WadRayMath for uint256;

import { console2 } from "forge-std/console2.sol";

struct Config {
    uint256 initialDepositLowerBound;
}

// TODO: The base contracts are currently not market agnostic
abstract contract UniswapFlashswapDirectMintHandlerWithDust_FuzzTest is LrtHandler_ForkBase {
    Config ufdmConfig;

    function testForkFuzz_FlashswapAndMint(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, ufdmConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);

        weth.approve(address(_getTypedUFDMHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFDMHandler()));

        uint256 ilkRate = ionPool.rate(_getIlkIndex());
        uint256 ilkSpot = ionPool.spot(_getIlkIndex()).getSpot();

        // uint256 maxResultingDebt = resultingCollateral * ilkSpot / 1e27;
        uint256 maxResultingDebt =
            _getProviderLibrary().getEthAmountInForLstAmountOut(resultingCollateral - initialDeposit);
        console2.log("maxResultingDebt: ", maxResultingDebt);

        // Calculating this way emulates the newTotalDebt value in IonPool
        uint256 newTotalDebt = maxResultingDebt.rayDivUp(ilkRate) * ilkRate;

        bool unsafePositionChange = newTotalDebt > resultingCollateral * ilkSpot;

        vm.assume(!unsafePositionChange);

        _getTypedUFDMHandler().flashswapAndMint(
            initialDeposit, resultingCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;
        if (currentRate % RAY != 0) roundingError++;

        // TODO: calculate this dust amount
        uint256 maxDust = 300_000;

        assertLt(
            ionPool.collateral(_getIlkIndex(), address(this)),
            resultingCollateral + maxDust,
            "resulting collateral with dust is above the minimum amount to mint"
        );
        assertEq(IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedUFDMHandler())), 0);
        assertLe(IERC20(_getUnderlying()).balanceOf(address(_getTypedUFDMHandler())), roundingError);
        assertLe(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt + roundingError
        );
    }

    function _getTypedUFDMHandler() internal view returns (UniswapFlashswapDirectMintHandlerWithDust) {
        return UniswapFlashswapDirectMintHandlerWithDust(payable(_getHandler()));
    }
}

abstract contract UniswapFlashswapDirectMintHandlerWithDust_WithRateChange_FuzzTest is
    UniswapFlashswapDirectMintHandlerWithDust_FuzzTest
{
    function testForkFuzz_WithRateChange_FlashswapAndMint(
        uint256 initialDeposit,
        uint256 resultingCollateralMultiplier,
        uint104 rate
    )
        external
    {
        rate = uint104(bound(rate, 1e27, 10e27));
        ionPool.setRate(_getIlkIndex(), rate);
        super.testForkFuzz_FlashswapAndMint(initialDeposit, resultingCollateralMultiplier);
    }
}
