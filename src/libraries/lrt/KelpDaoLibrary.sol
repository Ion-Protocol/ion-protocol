// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IRsEth } from "../../interfaces/ProviderInterfaces.sol";
import { RSETH_LRT_DEPOSIT_POOL, RSETH_LRT_ORACLE, ETH_ADDRESS } from "../../Constants.sol";
import { WadRayMath, WAD } from "../math/WadRayMath.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using WadRayMath for uint256;
using Math for uint256;

/**
 * @title KelpDaoLibrary
 *
 * @notice A helper library for KelpDao-related conversions.
 */
library KelpDaoLibrary {
    /**
     * @notice Deposits a given amount of ETH into the rsETH Deposit Pool.
     * @dev Care should be taken to handle slippage in the calling function
     * since this function sets NO slippage controls.
     *
     * @param ethAmount Amount of ETH to deposit. [WAD]
     * @return rsEthAmountToMint Amount of rsETH that was obtained. [WAD]
     */
    function depositForLrt(IRsEth, uint256 ethAmount) internal returns (uint256 rsEthAmountToMint) {
        rsEthAmountToMint = RSETH_LRT_DEPOSIT_POOL.getRsETHAmountToMint(ETH_ADDRESS, ethAmount);

        // Intentionally skip the slippage check and allow it to be handled by
        // function caller. This function is meant to be used in the handler
        // which has its own slippage check through `maxResultingDebt`.
        RSETH_LRT_DEPOSIT_POOL.depositETH{ value: ethAmount }(0, "");
    }

    /**
     * @notice Returns the amount of ETH required to mint a given amount of rsETH.
     * @param amountOut Desired output amount of rsETH
     */
    function getEthAmountInForLstAmountOut(IRsEth, uint256 amountOut) internal view returns (uint256) {
        // getRsEthAmountToMint
        // rsEthAmountToMint = floor(amount * assetPrice / rsETHPrice)
        // assetPrice for ETH is always 1e18 on the contract
        // rsEthAmountToMint * rsETHPrice / assetPrice = amount
        // round up the amount to ensure that the user has enough to mint the rsETH

        return amountOut.mulDiv(RSETH_LRT_ORACLE.rsETHPrice(), WAD, Math.Rounding.Ceil);
    }

    /**
     * @notice Calculates the amount of rsETH that will be minted for a given amount of ETH.
     * @param ethAmount Amount of ETH to use to mint rsETH
     * @return Amount of outputted rsETH for a given amount of ETH
     */
    function getLstAmountOutForEthAmountIn(IRsEth, uint256 ethAmount) internal view returns (uint256) {
        return RSETH_LRT_DEPOSIT_POOL.getRsETHAmountToMint(ETH_ADDRESS, ethAmount);
    }
}
