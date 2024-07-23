// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "./../../../IonPool.sol";
import { IonPool } from "./../../../IonPool.sol";
import { GemJoin } from "./../../../join/GemJoin.sol";
import { Whitelist } from "./../../../Whitelist.sol";
import { IonHandlerBase } from "./../../IonHandlerBase.sol";
import { IWETH9 } from "./../../../interfaces/IWETH9.sol";
import { UniswapFlashswapHandler } from "./../../UniswapFlashswapHandler.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @notice Handler for the ezETH collateral in the ezETH/WETH market on Base.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract BaseEzEthWethHandler is UniswapFlashswapHandler {
    /**
     * @notice Creates a new `EzEthWethHandler` instance.
     * @param _ilkIndex Ilk index of the pool.
     * @param _ionPool address.
     * @param _gemJoin address.
     * @param _whitelist address.
     * @param _pool address of the ezETH/WETH Aerodrome pool.
     * @param _wethIsToken0 Whether WETH is token0 or token1.
     * @param _weth The WETH address of this chain.
     */
    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IUniswapV3Pool _pool,
        bool _wethIsToken0,
        IWETH9 _weth
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist, _weth)
        UniswapFlashswapHandler(_pool, _wethIsToken0)
    { }
}
