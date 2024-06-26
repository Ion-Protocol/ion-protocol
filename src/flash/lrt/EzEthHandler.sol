// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { Whitelist } from "../../Whitelist.sol";
import { UniswapFlashswapDirectMintHandlerWithDust } from "./../UniswapFlashswapDirectMintHandlerWithDust.sol";
import { IonHandlerBase } from "../IonHandlerBase.sol";
import { RenzoLibrary } from "./../../libraries/lrt/RenzoLibrary.sol";
import { WETH_ADDRESS } from "../../Constants.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @notice Handler for the ezETH collateral.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EzEthHandler is UniswapFlashswapDirectMintHandlerWithDust {
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
        IUniswapV3Pool _wstEthUniswapPool
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
        UniswapFlashswapDirectMintHandlerWithDust(_wstEthUniswapPool, WETH_ADDRESS)
    { }

    /**
     * @inheritdoc UniswapFlashswapDirectMintHandlerWithDust
     */
    function _mintCollateralAsset(uint256 amountWeth) internal override returns (uint256) {
        WETH.withdraw(amountWeth);
        return RenzoLibrary.depositForLrt(amountWeth);
    }

    /**
     * @inheritdoc UniswapFlashswapDirectMintHandlerWithDust
     */
    function _getAmountInForCollateralAmountOut(uint256 amountOut)
        internal
        view
        override
        returns (uint256 ethAmountIn)
    {
        (ethAmountIn,) = RenzoLibrary.getEthAmountInForLstAmountOut(amountOut);
    }
}
