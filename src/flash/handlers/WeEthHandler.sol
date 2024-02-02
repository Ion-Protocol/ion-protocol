// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { IStaderStakePoolsManager, IWeEth } from "../../interfaces/ProviderInterfaces.sol";
import { Whitelist } from "../../Whitelist.sol";
import { UniswapFlashswapDirectMintHandler } from "./base/UniswapFlashswapDirectMintHandler.sol";
import { IonHandlerBase } from "./base/IonHandlerBase.sol";
import { EtherFiLibrary } from "../../libraries/EtherFiLibrary.sol";
import { WEETH_ADDRESS, EETH_ADDRESS } from "../../Constants.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract WeEthHandler is UniswapFlashswapDirectMintHandler {
    using EtherFiLibrary for IWeEth;

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IUniswapV3Pool _wstEthUniswapPool
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
        UniswapFlashswapDirectMintHandler(_wstEthUniswapPool)
    {
        EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
    }

    function _depositWethForLrt(uint256 amountWeth) internal override returns (uint256) {
        WETH.withdraw(amountWeth);
        return WEETH_ADDRESS.depositForLrt(amountWeth);
    }

    function _getEthAmountInForLstAmountOut(uint256 amountLrt) internal view override returns (uint256) {
        return WEETH_ADDRESS.getEthAmountInForLstAmountOut(amountLrt);
    }
}
