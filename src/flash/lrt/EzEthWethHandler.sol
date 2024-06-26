// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { Whitelist } from "../../Whitelist.sol";
import { IonHandlerBase } from "../IonHandlerBase.sol";
import { UniswapFlashloanBalancerSwapHandler } from "./../UniswapFlashloanBalancerSwapHandler.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @notice Handler for the ezETH collateral in the ezETH/WETH market.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EzEthWethHandler is UniswapFlashloanBalancerSwapHandler {
    /**
     * @notice Creates a new `EzEthWethHandler` instance.
     * @param _ilkIndex Ilk index of the pool.
     * @param _ionPool address.
     * @param _gemJoin address.
     * @param _whitelist address.
     * @param _wstEthUniswapPool address of the wstETH/WETH Uniswap pool
     * @param _balancerPoolId Balancer pool ID for the ezETH/WETH pool.
     */
    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IUniswapV3Pool _wstEthUniswapPool,
        bytes32 _balancerPoolId
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
        UniswapFlashloanBalancerSwapHandler(_wstEthUniswapPool, _balancerPoolId)
    { }
}
