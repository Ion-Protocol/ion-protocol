// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { IonRegistry } from "src/IonRegistry.sol";
import { IonHandlerBase } from "./base/IonHandlerBase.sol";
import { UniswapFlashswapHandler } from "./base/UniswapFlashswapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "./base/BalancerFlashloanDirectMintHandler.sol";
import { ISwellDeposit } from "src/interfaces/DepositInterfaces.sol";
import { SwellLibrary } from "src/libraries/SwellLibrary.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import { Whitelist } from "src/Whitelist.sol";

contract SwEthHandler is UniswapFlashswapHandler, BalancerFlashloanDirectMintHandler {
    using RoundedMath for uint256;
    using SwellLibrary for ISwellDeposit;

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        IonRegistry _ionRegistry,
        Whitelist _whitelist,
        IUniswapV3Factory _factory,
        IUniswapV3Pool _swEthPool,
        uint24 _poolFee
    )
        IonHandlerBase(_ilkIndex, _ionPool, _ionRegistry, _whitelist)
        UniswapFlashswapHandler(_factory, _swEthPool, _poolFee, true)
    { }

    function _depositWethForLst(uint256 wethAmount) internal override returns (uint256) {
        weth.withdraw(wethAmount);
        return ISwellDeposit(address(lstToken)).depositForLst(wethAmount);
    }
}
