// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IStEth } from "../interfaces/ProviderInterfaces.sol";
import { IWstEth } from "../interfaces/ProviderInterfaces.sol";
import { WadRayMath } from "../libraries/math/WadRayMath.sol";

library LidoLibrary {
    using WadRayMath for uint256;

    error WstEthDepositFailed();

    function getEthAmountInForLstAmountOut(IWstEth wstEth, uint256 lstAmount) internal view returns (uint256) {
        IStEth stEth = IStEth(wstEth.stETH());
        return lstAmount.wadMulDown(stEth.getTotalPooledEther()).wadDivUp(stEth.getTotalShares());
    }

    function getLstAmountOutForEthAmountIn(IWstEth wstEth, uint256 ethAmount) internal view returns (uint256) {
        // lstToken and depositContract are same
        return IWstEth(address(wstEth)).getWstETHByStETH(ethAmount);
    }

    function depositForLst(IWstEth wstEth, uint256 ethAmount) internal returns (uint256) {
        (bool success,) = address(wstEth).call{ value: ethAmount }("");
        if (!success) revert WstEthDepositFailed();

        return getLstAmountOutForEthAmountIn(wstEth, ethAmount);
    }
}
