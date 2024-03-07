// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { IonHandlerBase } from "../IonHandlerBase.sol";
import { UniswapFlashswapHandler } from "../UniswapFlashswapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "../BalancerFlashloanDirectMintHandler.sol";
import { ISwEth } from "../../interfaces/ProviderInterfaces.sol";
import { SwellLibrary } from "../../libraries/lst/SwellLibrary.sol";
import { WadRayMath } from "../../libraries/math/WadRayMath.sol";
import { Whitelist } from "../../Whitelist.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @notice Handler for the swETH collateral.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract SwEthHandler is UniswapFlashswapHandler, BalancerFlashloanDirectMintHandler {
    using WadRayMath for uint256;
    using SwellLibrary for ISwEth;

    /**
     * @notice Creates a new `SwEthHandler` instance.
     * @param _ilkIndex of swETH.
     * @param _ionPool `IonPool` contract address.
     * @param _gemJoin `GemJoin` contract address associated with swETH.
     * @param _whitelist Address of the `Whitelist` contract.
     * @param _swEthPool Address of the swETH/ETH Uniswap V3 pool.
     */
    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IUniswapV3Pool _swEthPool
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
        UniswapFlashswapHandler(_swEthPool, true)
    { }

    /**
     * @notice Unwraps weth into eth and deposits into lst contract.
     * @dev Unwraps weth into eth and deposits into lst contract.
     * @param amountWeth The WETH amount to deposit. [WAD]
     * @return Amount of lst received. [WAD]
     */
    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        WETH.withdraw(amountWeth);
        return ISwEth(address(LST_TOKEN)).depositForLst(amountWeth);
    }

    /**
     * @notice Calculates the amount of eth required to receive `amountLst`.
     * @dev Calculates the amount of eth required to receive `amountLst`.
     * @param amountLst Desired output amount. [WAD]
     * @return Eth required for desired lst output. [WAD]
     */
    function _getEthAmountInForLstAmountOut(uint256 amountLst) internal view override returns (uint256) {
        return ISwEth(address(LST_TOKEN)).getEthAmountInForLstAmountOut(amountLst);
    }
}
