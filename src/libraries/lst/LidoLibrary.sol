// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IStEth } from "../../interfaces/ProviderInterfaces.sol";
import { IWstEth } from "../../interfaces/ProviderInterfaces.sol";
import { WadRayMath } from "../../libraries/math/WadRayMath.sol";

/**
 * @title LidoLibrary
 *
 * @notice A helper library for Lido-related conversions.
 *
 * @custom:security-contact security@molecularlabs.io
 */
library LidoLibrary {
    using WadRayMath for uint256;

    error WstEthDepositFailed();

    /**
     * @notice Returns the amount of ETH needed to mint the given amount of wstETH.
     * @param wstEth address.
     * @param lstAmount Desired output amount. [WAD]
     */
    function getEthAmountInForLstAmountOut(IWstEth wstEth, uint256 lstAmount) internal view returns (uint256) {
        IStEth stEth = IStEth(wstEth.stETH());
        return lstAmount.wadMulDown(stEth.getTotalPooledEther()).wadDivUp(stEth.getTotalShares());
    }

    /**
     * @notice Returns the amount of wstETH that can be minted with the given amount of ETH.
     * @param wstEth address.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     */
    function getLstAmountOutForEthAmountIn(IWstEth wstEth, uint256 ethAmount) internal view returns (uint256) {
        // lstToken and depositContract are same
        return wstEth.getWstETHByStETH(ethAmount);
    }

    /**
     * @notice Deposits ETH into the wstETH contract and returns the amount of wstETH received.
     * @param wstEth address.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     */
    function depositForLst(IWstEth wstEth, uint256 ethAmount) internal returns (uint256) {
        (bool success,) = address(wstEth).call{ value: ethAmount }("");
        if (!success) revert WstEthDepositFailed();

        return getLstAmountOutForEthAmountIn(wstEth, ethAmount);
    }
}
