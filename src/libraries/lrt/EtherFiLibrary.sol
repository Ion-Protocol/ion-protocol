// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IWeEth, IEEth, IEtherFiLiquidityPool } from "../../interfaces/ProviderInterfaces.sol";
import { WadRayMath } from "../math/WadRayMath.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using Math for uint256;
using WadRayMath for uint256;

/**
 * @title EtherFiLibrary
 *
 * @notice A helper library for EtherFi-related conversions.
 *
 * @custom:security-contact security@molecularlabs.io
 */
library EtherFiLibrary {
    error NoAmountInFound();

    /**
     * @notice Returns the amount of ETH required to obtain a given amount of weETH.
     * @dev Performing the calculations seems to potentially yield a rounding
     * error of 1-2 wei. In order to ensure that the correct value is returned,
     * both versions are tested and the correct one is returned.
     *
     * Should a correct version ever not be found, any contracts using the
     * library should halt execution.
     * @param weEth contract.
     * @param lrtAmount Desired amount of weETH. [WAD]
     * @return Amount of ETH required to obtain the given amount of weETH. [WAD]
     */
    function getEthAmountInForLstAmountOut(IWeEth weEth, uint256 lrtAmount) internal view returns (uint256) {
        if (lrtAmount == 0) return 0;

        IEtherFiLiquidityPool pool = IEtherFiLiquidityPool(weEth.liquidityPool());
        IEEth eEth = IEEth(weEth.eETH());

        uint256 totalPooledEther = pool.getTotalPooledEther();
        uint256 totalShares = eEth.totalShares();

        uint256 unroundedAmountIn = lrtAmount.wadMulDown(totalPooledEther).wadDivUp(totalShares) + 1;

        // Rounding error tends to be ~1-2 wei. Check both options and return the correct one.
        if (_getLstAmountOutForEthAmountIn(totalPooledEther, totalShares, unroundedAmountIn) == lrtAmount) {
            return unroundedAmountIn;
        }
        if (_getLstAmountOutForEthAmountIn(totalPooledEther, totalShares, unroundedAmountIn + 1) == lrtAmount) {
            return unroundedAmountIn + 1;
        }

        // Let's be defensive. If the rounding cannot be solved... create a DOS.
        revert NoAmountInFound();
    }

    /**
     * @notice Returns the amount of weETH that will be obtained from a given amount of ETH.
     * @param weEth contract.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     * @return Amount of weETH that will be obtained. [WAD]
     */
    function getLstAmountOutForEthAmountIn(IWeEth weEth, uint256 ethAmount) internal view returns (uint256) {
        IEtherFiLiquidityPool pool = IEtherFiLiquidityPool(weEth.liquidityPool());
        IEEth eEth = IEEth(weEth.eETH());

        uint256 totalPooledEther = pool.getTotalPooledEther();
        uint256 totalShares = eEth.totalShares();

        return _getLstAmountOutForEthAmountIn(totalPooledEther, totalShares, ethAmount);
    }

    /**
     * @notice An internal helper function to calculate the amount of weETH that
     * will be obtained from a given amount of ETH.
     * @dev This is useful if the function arguments are already known so that
     * additional external calls can be avoided.
     * @param totalPooledEther Total pooled ether in the Ether Fi pool. [WAD]
     * @param totalShares Total amount of minted shares. [WAD]
     * @param ethAmount Amount of ETH to deposit. [WAD]
     * @return Amount of weETH that will be obtained. [WAD]
     */
    function _getLstAmountOutForEthAmountIn(
        uint256 totalPooledEther,
        uint256 totalShares,
        uint256 ethAmount
    )
        internal
        pure
        returns (uint256)
    {
        uint256 eEthSharesAmount = _sharesForAmount(totalPooledEther, totalShares, ethAmount);
        uint256 newTotalPooledEther = totalPooledEther + ethAmount;
        if (newTotalPooledEther == 0) return 0;

        uint256 newTotalShares = totalShares + eEthSharesAmount;
        uint256 eEthAmount = _amountForShares(newTotalPooledEther, newTotalShares, eEthSharesAmount);

        return _sharesForAmount(newTotalPooledEther, newTotalShares, eEthAmount);
    }

    /**
     * @notice Deposits a given amount of ETH into the Ether Fi pool and then
     * uses the received eETH to mint weETH.
     * @param weEth contract.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     * @return Amount of weETH that was obtained. [WAD]
     */
    function depositForLrt(IWeEth weEth, uint256 ethAmount) internal returns (uint256) {
        IEtherFiLiquidityPool pool = IEtherFiLiquidityPool(weEth.liquidityPool());
        uint256 eEthSharesAmount = pool.deposit{ value: ethAmount }();

        uint256 newTotalPooledEther = pool.getTotalPooledEther();
        uint256 newTotalShares = IEEth(weEth.eETH()).totalShares();
        uint256 amountEEthRecieved = _amountForShares(newTotalPooledEther, newTotalShares, eEthSharesAmount);
        return weEth.wrap(amountEEthRecieved);
    }

    /**
     * @notice An internal helper function to calculate the amount of shares
     * from amount.
     * @dev Useful for avoiding external calls when the function arguments are
     * already known.
     * @param totalPooledEther Total pooled ether in the Ether Fi pool. [WAD]
     * @param totalShares Total amount of minted shares. [WAD]
     * @param _depositAmount Amount of ETH. [WAD]
     */
    function _sharesForAmount(
        uint256 totalPooledEther,
        uint256 totalShares,
        uint256 _depositAmount
    )
        internal
        pure
        returns (uint256)
    {
        if (totalPooledEther == 0) return _depositAmount;

        return (_depositAmount * totalShares) / totalPooledEther;
    }

    /**
     * @notice An internal helper function to calculate the amount from given
     * amount of shares.
     * @dev Useful for avoiding external calls when the function arguments are
     * already known.
     * @param totalPooledEther Total pooled ether in the Ether Fi pool. [WAD]
     * @param totalShares Total amount of minted shares. [WAD]
     * @param _shares Amount of shares. [WAD]
     */
    function _amountForShares(
        uint256 totalPooledEther,
        uint256 totalShares,
        uint256 _shares
    )
        internal
        pure
        returns (uint256)
    {
        return (_shares * totalPooledEther) / totalShares;
    }
}
