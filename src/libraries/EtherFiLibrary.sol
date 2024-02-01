// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWeEth, IEEth, IEtherFiLiquidityPool } from "../interfaces/ProviderInterfaces.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { WadRayMath } from "./math/WadRayMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

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
    function getEthAmountInForLstAmountOut(IWeEth weEth, uint256 lrtAmount) internal view returns (uint256) {
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
        revert("EtherFiLibrary: getEthAmountInForLstAmountOut: no solution found");
    }

    function getLstAmountOutForEthAmountIn(IWeEth weEth, uint256 ethAmount) internal view returns (uint256) {
        IEtherFiLiquidityPool pool = IEtherFiLiquidityPool(weEth.liquidityPool());
        IEEth eEth = IEEth(weEth.eETH());

        uint256 totalPooledEther = pool.getTotalPooledEther();
        uint256 totalShares = eEth.totalShares();

        return _getLstAmountOutForEthAmountIn(totalPooledEther, totalShares, ethAmount);
    }

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

    function depositForLrt(IWeEth weEth, uint256 ethAmount) internal returns (uint256) {
        IEtherFiLiquidityPool pool = IEtherFiLiquidityPool(weEth.liquidityPool());
        uint256 eEthSharesAmount = pool.deposit{ value: ethAmount }();

        uint256 newTotalPooledEther = pool.getTotalPooledEther();
        uint256 newTotalShares = IEEth(weEth.eETH()).totalShares();
        uint256 amountEEthRecieved = _amountForShares(newTotalPooledEther, newTotalShares, eEthSharesAmount);
        return weEth.wrap(amountEEthRecieved);
    }

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
