// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { GemJoin } from "src/join/GemJoin.sol";
import { IonHandlerBase } from "./base/IonHandlerBase.sol";
import { UniswapFlashswapHandler } from "./base/UniswapFlashswapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "./base/BalancerFlashloanDirectMintHandler.sol";
import { ISwEth } from "src/interfaces/ProviderInterfaces.sol";
import { SwellLibrary } from "src/libraries/SwellLibrary.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import { Whitelist } from "src/Whitelist.sol";

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
        weth.withdraw(wethAmount);
        return ISwEth(address(lstToken)).depositForLst(wethAmount);
    }

    function _getEthAmountInForLstAmountOut(uint256 lstAmount) internal view override returns (uint256) {
        return ISwEth(address(lstToken)).getEthAmountInForLstAmountOut(lstAmount);
    }
}
