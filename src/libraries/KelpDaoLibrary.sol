// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IRsEth } from "../interfaces/ProviderInterfaces.sol";
import { RSETH_LRT_DEPOSIT_POOL, RSETH_LRT_ORACLE, ETH_ADDRESS } from "../Constants.sol";
import { WadRayMath, WAD } from "./math/WadRayMath.sol";

using WadRayMath for uint256;

library KelpDaoLibrary {
    /**
     * @notice Deposits a given amount of ETH into the rsETH Deposit Pool.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     * @return rsEthAmountToMint Amount of rsETH that was obtained. [WAD]
     */
    function depositForLrt(IRsEth rsEth, uint256 ethAmount) internal returns (uint256 rsEthAmountToMint) {
        rsEthAmountToMint = RSETH_LRT_DEPOSIT_POOL.getRsETHAmountToMint(ETH_ADDRESS, ethAmount);
        RSETH_LRT_DEPOSIT_POOL.depositETH{ value: ethAmount }(0, ""); // TODO: slippage tolerance on mint
    }

    function getEthAmountInForLstAmountOut(IRsEth rsEth, uint256 amountOut) internal view returns (uint256) {
        // getRsEthAmountToMint
        // rsEthAmountToMint = floor(amount * assetPrice / rsETHPrice)
        // assetPrice for ETH is always 1e18 on the contract
        // rsEthAmountToMint * rsETHPrice / assetPrice = amount
        // round up the amount to ensure that the user has enough to mint the rsETH

        return amountOut.wadMulDown(RSETH_LRT_ORACLE.rsETHPrice()).wadDivUp(WAD);
    }

    function getLstAmountOutForEthAmountIn(IRsEth rsEth, uint256 ethAmount) internal view returns (uint256) {
        return RSETH_LRT_DEPOSIT_POOL.getRsETHAmountToMint(ETH_ADDRESS, ethAmount);
    }
}
