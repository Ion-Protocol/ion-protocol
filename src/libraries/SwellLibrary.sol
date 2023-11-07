// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WadRayMath } from "src/libraries/math/WadRayMath.sol";
import { ISwEth } from "src/interfaces/ProviderInterfaces.sol";

library SwellLibrary {
    using WadRayMath for uint256;

    function getEthAmountInForLstAmountOut(ISwEth swEth, uint256 lstAmount) internal view returns (uint256) {
        return lstAmount.wadDivUp(swEth.ethToSwETHRate());
    }

    function getLstAmountOutForEthAmountIn(ISwEth swEth, uint256 ethAmount) internal view returns (uint256) {
        // lstToken and depositContract are same
        return swEth.ethToSwETHRate().wadMulDown(ethAmount);
    }

    function depositForLst(ISwEth swEth, uint256 ethAmount) internal returns (uint256) {
        swEth.deposit{ value: ethAmount }();
        return getLstAmountOutForEthAmountIn(swEth, ethAmount);
    }
}
