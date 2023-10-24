// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ILidoStEthDeposit } from "../../src/interfaces/DepositInterfaces.sol";
import { ILidoWStEthDeposit } from "../../src/interfaces/DepositInterfaces.sol";
import { RoundedMath } from "../../src/libraries/math/RoundedMath.sol";

library LidoLibrary {
    using RoundedMath for uint256;

    error WstEthDepositFailed();

    function getEthAmountInForLstAmountOut(
        ILidoWStEthDeposit wstEth,
        uint256 lstAmount
    )
        internal
        view
        returns (uint256)
    {
        ILidoStEthDeposit stEth = ILidoStEthDeposit(wstEth.stETH());
        return lstAmount.wadMulDown(stEth.getTotalPooledEther()).wadDivUp(stEth.getTotalShares());
    }

    function getLstAmountOutForEthAmountIn(
        ILidoWStEthDeposit wstEth,
        uint256 ethAmount
    )
        internal
        view
        returns (uint256)
    {
        // lstToken and depositContract are same
        return ILidoWStEthDeposit(address(wstEth)).getWstETHByStETH(ethAmount);
    }

    function depositForLst(ILidoWStEthDeposit wstEth, uint256 ethAmount) internal returns (uint256) {
        (bool success,) = address(wstEth).call{ value: ethAmount }("");
        if (!success) revert WstEthDepositFailed();

        return getLstAmountOutForEthAmountIn(wstEth, ethAmount);
    }
}
