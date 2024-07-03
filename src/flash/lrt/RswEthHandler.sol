// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { IRswEth } from "../../interfaces/ProviderInterfaces.sol";
import { Whitelist } from "../../Whitelist.sol";
import { UniswapFlashswapDirectMintHandler } from "../UniswapFlashswapDirectMintHandler.sol";
import { IonHandlerBase } from "../IonHandlerBase.sol";
import { RSWETH, WETH_ADDRESS } from "../../Constants.sol";
import { RestakedSwellLibrary } from "../../libraries/lrt/RestakedSwellLibrary.sol";
import { IWETH9 } from "./../../interfaces/IWETH9.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @notice Handler for the rswETH/wstETH market.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract RswEthHandler is UniswapFlashswapDirectMintHandler {
    using RestakedSwellLibrary for IRswEth;

    /**
     * @notice Creates a new `RswEthHandler` instance.
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
        IUniswapV3Pool _wstEthUniswapPool,
        IWETH9 _weth
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist, _weth)
        UniswapFlashswapDirectMintHandler(_wstEthUniswapPool, WETH_ADDRESS)
    { }

    /**
     * @inheritdoc UniswapFlashswapDirectMintHandler
     */
    function _mintCollateralAsset(uint256 amountWeth) internal override returns (uint256) {
        WETH.withdraw(amountWeth);
        return RSWETH.depositForLrt(amountWeth);
    }

    /**
     * @inheritdoc UniswapFlashswapDirectMintHandler
     */
    function _getAmountInForCollateralAmountOut(uint256 amountOut) internal view override returns (uint256) {
        return RSWETH.getEthAmountInForLstAmountOut(amountOut);
    }

    /**
     * @notice Returns the amount of ETH needed to mint the given amount of rswETH.
     * @param lstAmount Desired output amount. [WAD]
     */
    function getEthAmountInForLstAmountOut(uint256 lstAmount) external view returns (uint256) {
        return RSWETH.getEthAmountInForLstAmountOut(lstAmount);
    }

    /**
     * @notice Returns the amount of ETH needed to mint the given amount of rswETH.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     */
    function getLstAmountOutForEthAmountIn(uint256 ethAmount) external view returns (uint256) {
        return RSWETH.getLstAmountOutForEthAmountIn(ethAmount);
    }
}
