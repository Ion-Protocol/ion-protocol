// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { ISwellDeposit } from "src/interfaces/DepositInterfaces.sol";

library SwellLibrary {
    using RoundedMath for uint256;

    function getEthAmountInForLstAmountOut(ISwellDeposit swEth, uint256 lstAmount) internal view returns (uint256) {
        return lstAmount.wadDivUp(swEth.ethToSwETHRate());
    }

    function getLstAmountOutForEthAmountIn(ISwellDeposit swEth, uint256 ethAmount) internal view returns (uint256) {
        // lstToken and depositContract are same
        return swEth.ethToSwETHRate().wadMulDown(ethAmount);
    }

    function depositForLst(ISwellDeposit swEth, uint256 ethAmount) internal returns (uint256) {
        swEth.deposit{ value: ethAmount }();
        return getLstAmountOutForEthAmountIn(swEth, ethAmount);
    }
}
