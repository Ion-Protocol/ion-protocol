// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { IonRegistry } from "src/IonRegistry.sol";
import { IonHandlerBase } from "./base/IonHandlerBase.sol";
import { UniswapFlashswapHandler } from "./base/UniswapFlashswapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "./base/BalancerFlashloanDirectMintHandler.sol";
import { ILidoWStEthDeposit } from "src/interfaces/DepositInterfaces.sol";
import { LidoLibrary } from "src/libraries/LidoLibrary.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import { Whitelist } from "src/Whitelist.sol";

contract WstEthHandler is UniswapFlashswapHandler, BalancerFlashloanDirectMintHandler {
    using LidoLibrary for ILidoWStEthDeposit;

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        IonRegistry _ionRegistry,
        Whitelist _whitelist,
        IUniswapV3Factory _factory,
        IUniswapV3Pool _wstEthUniswapPool,
        uint24 _poolFee
    )
        IonHandlerBase(_ilkIndex, _ionPool, _ionRegistry, _whitelist)
        // token0 is wstEth
        UniswapFlashswapHandler(_factory, _wstEthUniswapPool, _poolFee, false)
    { }

    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        weth.withdraw(amountWeth);
        return ILidoWStEthDeposit(address(lstToken)).depositForLst(amountWeth);
    }
}
