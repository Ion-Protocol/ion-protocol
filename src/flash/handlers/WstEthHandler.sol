// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { IonHandlerBase } from "./base/IonHandlerBase.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { UniswapFlashswapHandler } from "./base/UniswapFlashswapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "./base/BalancerFlashloanDirectMintHandler.sol";
import { IWstEth } from "../../interfaces/ProviderInterfaces.sol";
import { LidoLibrary } from "../../libraries/LidoLibrary.sol";
import { Whitelist } from "../../Whitelist.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

/**
 * @notice Handler for the WstEth collateral.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract WstEthHandler is UniswapFlashswapHandler, BalancerFlashloanDirectMintHandler {
    using LidoLibrary for IWstEth;

    /**
     * @notice Creates a new `WstEthHandler` instance.
     * @param _ilkIndex of WstEth.
     * @param _ionPool `IonPool` contract address.
     * @param _gemJoin `GemJoin` contract address associated with WstEth.
     * @param _whitelist Address of the `Whitelist` contract.
     * @param _wstEthUniswapPool Adderess of the WstEth/ETH Uniswap V3 pool.
     */
    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IUniswapV3Pool _wstEthUniswapPool
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
        // token0 is wstEth
        UniswapFlashswapHandler(_wstEthUniswapPool, false)
    { }

    /**
     * @notice Unwraps weth into eth and deposits into lst contract.
     * @dev Unwraps weth into eth and deposits into lst contract.
     * @param amountWeth to deposit. [WAD]
     * @return Amount of lst received. [WAD]
     */
    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        WETH.withdraw(amountWeth);
        return IWstEth(address(LST_TOKEN)).depositForLst(amountWeth);
    }

    /**
     * @notice Calculates the amount of eth required to receive `amountLst`.
     * @dev Calculates the amount of eth required to receive `amountLst`.
     * @param amountLst desired output amount. [WAD]
     * @return Eth required for desired lst output. [WAD]
     */
    function _getEthAmountInForLstAmountOut(uint256 amountLst) internal view override returns (uint256) {
        return IWstEth(address(LST_TOKEN)).getEthAmountInForLstAmountOut(amountLst);
    }
}
