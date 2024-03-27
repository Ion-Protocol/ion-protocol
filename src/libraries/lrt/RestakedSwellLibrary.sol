// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { WadRayMath } from "../../libraries/math/WadRayMath.sol";
import { IRswEth } from "../../interfaces/ProviderInterfaces.sol";

/**
 * @title RestakedSwellLibrary
 *
 * @notice A helper library for restaked Swell-related conversions.
 *
 * @custom:security-contact security@molecularlabs.io
 */
library RestakedSwellLibrary {
    using WadRayMath for uint256;

    /**
     * @notice Returns the amount of ETH needed to mint the given amount of rswETH.
     * @param rswEth address.
     * @param lstAmount Desired output amount. [WAD]
     */
    function getEthAmountInForLstAmountOut(IRswEth rswEth, uint256 lstAmount) internal view returns (uint256) {
        return lstAmount.wadDivUp(rswEth.ethToRswETHRate());
    }

    /**
     * @notice Returns the amount of ETH needed to mint the given amount of rswETH.
     * @param rswEth address.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     */
    function getLstAmountOutForEthAmountIn(IRswEth rswEth, uint256 ethAmount) internal view returns (uint256) {
        // lstToken and depositContract are same
        return ethAmount.wadMulDown(rswEth.ethToRswETHRate());
    }

    /**
     * @notice Deposits ETH into the rswETH contract and returns the amount of rswETH received.
     * @param rswEth address.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     */
    function depositForLrt(IRswEth rswEth, uint256 ethAmount) internal returns (uint256) {
        rswEth.deposit{ value: ethAmount }();
        return getLstAmountOutForEthAmountIn(rswEth, ethAmount);
    }
}
