// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { WadRayMath } from "../../libraries/math/WadRayMath.sol";
import { ISwEth } from "../../interfaces/ProviderInterfaces.sol";

/**
 * @title SwellLibrary
 *
 * @notice A helper library for Swell-related conversions.
 *
 * @custom:security-contact security@molecularlabs.io
 */
library SwellLibrary {
    using WadRayMath for uint256;

    /**
     * @notice Returns the amount of ETH needed to mint the given amount of swETH.
     * @param swEth address.
     * @param lstAmount Desired output amount. [WAD]
     */
    function getEthAmountInForLstAmountOut(ISwEth swEth, uint256 lstAmount) internal view returns (uint256) {
        return lstAmount.wadMulUp(swEth.swETHToETHRate());
    }

    /**
     *
     * @param swEth address.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     */
    function getLstAmountOutForEthAmountIn(ISwEth swEth, uint256 ethAmount) internal view returns (uint256) {
        // lstToken and depositContract are same
        return ethAmount.wadMulDown(uint256(1e18)).wadDivDown(swEth.swETHToETHRate());
    }

    /**
     * @notice Deposits ETH into the swETH contract and returns the amount of swETH received.
     * @param swEth address.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     */
    function depositForLst(ISwEth swEth, uint256 ethAmount) internal returns (uint256) {
        swEth.deposit{ value: ethAmount }();
        return getLstAmountOutForEthAmountIn(swEth, ethAmount);
    }
}
