// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { IonHandlerBase } from "./base/IonHandlerBase.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { UniswapFlashswapHandler } from "./base/UniswapFlashswapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "./base/BalancerFlashloanDirectMintHandler.sol";
import { IWstEth } from "../../interfaces/ProviderInterfaces.sol";
import { LidoLibrary } from "../../libraries/LidoLibrary.sol";
import { Whitelist } from "../../Whitelist.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract WstEthHandler is UniswapFlashswapHandler, BalancerFlashloanDirectMintHandler {
    using LidoLibrary for IWstEth;

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IUniswapV3Pool _wstEthUniswapPool
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
        // token0 is wstEth
        UniswapFlashswapHandler(_wstEthUniswapPool, false)
    { }

    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        WETH.withdraw(amountWeth);
        return IWstEth(address(LST_TOKEN)).depositForLst(amountWeth);
    }

    function _getEthAmountInForLstAmountOut(uint256 amountLst) internal view override returns (uint256) {
        return IWstEth(address(LST_TOKEN)).getEthAmountInForLstAmountOut(amountLst);
    }
}
