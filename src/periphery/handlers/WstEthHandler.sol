// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { IonRegistry } from "./../IonRegistry.sol";
import { UniswapHandler } from "./base/UniswapHandler.sol";
import { ILidoWStEthDeposit } from "../../interfaces/DepositInterfaces.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract WstEthHandler is UniswapHandler {
    error WstEthDepositFailed();

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        IonRegistry _ionRegistry,
        IUniswapV3Factory _factory,
        IUniswapV3Pool _wstEthUniswapPool,
        uint24 _poolFee
    )
        // token0 is wstEth
        UniswapHandler(_ilkIndex, _ionPool, _ionRegistry, _factory, _wstEthUniswapPool, _poolFee, false)
    { }

    function _getLstAmountOut(uint256 amountWeth) internal view override returns (uint256) {
        // lstToken and depositContract are same
        return ILidoWStEthDeposit(address(lstToken)).getWstETHByStETH(amountWeth);
    }

    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        weth.withdraw(amountWeth);

        (bool success,) = address(lstToken).call{ value: amountWeth }("");
        if (!success) revert WstEthDepositFailed();

        return _getLstAmountOut(amountWeth);
    }
}
