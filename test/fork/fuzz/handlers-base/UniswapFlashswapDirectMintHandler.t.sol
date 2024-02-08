// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WeEthIonHandler_ForkBase } from "../../../helpers/weETH/WeEthIonHandlerForkBase.sol";
import { UniswapFlashswapDirectMintHandler } from
    "../../../../src/flash/handlers/base/UniswapFlashswapDirectMintHandler.sol";
import { WadRayMath, RAY } from "../../../../src/libraries/math/WadRayMath.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

using WadRayMath for uint256;

struct Config {
    uint256 initialDepositLowerBound;
}

// TODO: The base contracts are currently not market agnostic
abstract contract UniswapFlashswapDirectMintHandler_FuzzTest is WeEthIonHandler_ForkBase {
    Config ufdmConfig;

    function testForkFuzz_FlashswapAndMint(uint256 initialDeposit, uint256 resultingCollateralMultiplier) public {
        initialDeposit = bound(initialDeposit, ufdmConfig.initialDepositLowerBound, INITIAL_THIS_UNDERLYING_BALANCE);
        uint256 resultingCollateral = initialDeposit * bound(resultingCollateralMultiplier, 1, 5);
        uint256 maxResultingDebt = resultingCollateral; // in weth. This is technically subject to slippage but we will
            // skip protecting for this in the test

        weth.approve(address(_getTypedUFDMHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFDMHandler()));

        _getTypedUFDMHandler().flashswapAndMint(
            initialDeposit, resultingCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingCollateral);
        assertEq(IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedUFDMHandler())), 0);
        assertLe(IERC20(_getUnderlying()).balanceOf(address(_getTypedUFDMHandler())), 0);
        assertLt(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt
        );
    }

    function _getTypedUFDMHandler() internal view returns (UniswapFlashswapDirectMintHandler) {
        return UniswapFlashswapDirectMintHandler(payable(_getHandler()));
    }
}

abstract contract UniswapFlashswapDirectMintHandler_WithRateChange_FuzzTest is
    UniswapFlashswapDirectMintHandler_FuzzTest
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
