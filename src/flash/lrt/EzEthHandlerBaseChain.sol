// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { Whitelist } from "../../Whitelist.sol";
import { AerodromeFlashswapHandler, IPool } from "./../AerodromeFlashswapHandler.sol";
import { IonHandlerBase } from "../IonHandlerBase.sol";
import { RenzoLibrary } from "./../../libraries/lrt/RenzoLibrary.sol";
import { WETH_ADDRESS } from "../../Constants.sol";

import { IWETH9 } from "./../../interfaces/IWETH9.sol";

/**
 * @notice Handler for the ezETH collateral.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EzEthHandlerBaseChain is AerodromeFlashswapHandler {
    /**
     * @notice Creates a new `EzEthHandler` instance.
     * @param _ilkIndex Ilk index of the pool.
     * @param _ionPool address.
     * @param _gemJoin address.
     * @param _whitelist address.
     * @param _wstEthUniswapPool address of the wstETH/WETH Uniswap pool (0.01% fee).
     */
    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IPool _wstEthUniswapPool,
        IWETH9 _weth
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist, _weth)
        AerodromeFlashswapHandler(_wstEthUniswapPool, true)
    { }

}
