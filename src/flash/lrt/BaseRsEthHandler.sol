// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { Whitelist } from "../../Whitelist.sol";
import { AerodromeFlashswapHandler, IPool } from "./../AerodromeFlashswapHandler.sol";
import { IonHandlerBase } from "../IonHandlerBase.sol";
import { WETH_ADDRESS } from "../../Constants.sol";

import { IWETH9 } from "./../../interfaces/IWETH9.sol";

/**
 * @notice Handler for the rsETH collateral.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract BaseRsEthHandler is AerodromeFlashswapHandler {
    /**
     * @notice Creates a new `RsEthHandler` instance.
     * @param _ilkIndex Ilk index of the pool.
     * @param _ionPool address.
     * @param _gemJoin address.
     * @param _whitelist address.
     * @param _wrsEthAerodromePool address of the wrsETH/WETH Aerodrome pool (0.3% fee).
     */
    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IPool _wrsEthAerodromePool,
        IWETH9 _weth
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist, _weth)
        AerodromeFlashswapHandler(_wrsEthAerodromePool, true)
    { }

}
