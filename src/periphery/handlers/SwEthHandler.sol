// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { IonRegistry } from "./../IonRegistry.sol";
import { IonHandlerBase } from "./base/IonHandlerBase.sol";
import { UniswapFlashswapHandler } from "./base/UniswapFlashswapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "./base/BalancerFlashloanDirectMintHandler.sol";
import { ISwellDeposit } from "../../interfaces/DepositInterfaces.sol";
import { SwellLibrary } from "src/libraries/SwellLibrary.sol";
import { RoundedMath } from "../../libraries/math/RoundedMath.sol";
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

    function _getLstAmountOut(uint256 wethAmount) internal view override returns (uint256) {
        // lstToken and depositContract are same
        return ISwellDeposit(address(lstToken)).getLstAmountOutForEthAmountIn(wethAmount);
    }

    function _depositWethForLst(uint256 wethAmount) internal override returns (uint256) {
        weth.withdraw(wethAmount);
        return ISwellDeposit(address(lstToken)).depositForLst(wethAmount);
    }
}
