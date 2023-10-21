// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { IonRegistry } from "./../IonRegistry.sol";
import { UniswapHandler } from "./base/UniswapHandler.sol";
import { ISwellDeposit } from "../../interfaces/DepositInterfaces.sol";
import { RoundedMath } from "../../libraries/math/RoundedMath.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract SwEthHandler is UniswapHandler {
    using RoundedMath for uint256;

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        IonRegistry _ionRegistry,
        IUniswapV3Factory _factory,
        IUniswapV3Pool _swEthPool
    )
        UniswapHandler(_ilkIndex, _ionPool, _ionRegistry, _factory, _swEthPool, true)
    { }

    function _getLstAmountOut(uint256 amountWeth) internal view override returns (uint256) {
        // lstToken and depositContract are same
        return ISwellDeposit(address(lstToken)).ethToSwETHRate().wadMulDown(amountWeth);
    }

    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        weth.withdraw(amountWeth);

        ISwellDeposit(address(lstToken)).deposit{ value: amountWeth }();

        return _getLstAmountOut(amountWeth);
    }
}
