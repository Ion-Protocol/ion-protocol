// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { IonHandlerBase } from "./base/IonHandlerBase.sol";
import { UniswapFlashswapHandler } from "./base/UniswapFlashswapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "./base/BalancerFlashloanDirectMintHandler.sol";
import { ISwEth } from "../../interfaces/ProviderInterfaces.sol";
import { SwellLibrary } from "../../libraries/SwellLibrary.sol";
import { WadRayMath } from "../../libraries/math/WadRayMath.sol";
import { Whitelist } from "../../Whitelist.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract SwEthHandler is UniswapFlashswapHandler, BalancerFlashloanDirectMintHandler {
    using WadRayMath for uint256;
    using SwellLibrary for ISwEth;

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IUniswapV3Factory _factory,
        IUniswapV3Pool _swEthPool,
        uint24 _poolFee
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
        UniswapFlashswapHandler(_factory, _swEthPool, _poolFee, true)
    { }

    function _depositWethForLst(uint256 wethAmount) internal override returns (uint256) {
        WETH.withdraw(wethAmount);
        return ISwEth(address(LST_TOKEN)).depositForLst(wethAmount);
    }

    function _getEthAmountInForLstAmountOut(uint256 lstAmount) internal view override returns (uint256) {
        return ISwEth(address(LST_TOKEN)).getEthAmountInForLstAmountOut(lstAmount);
    }
}
