// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { Whitelist } from "../../Whitelist.sol";
import { StaderLibrary } from "../../libraries/lst/StaderLibrary.sol";
import { IStaderStakePoolsManager } from "../../interfaces/ProviderInterfaces.sol";
import { IonHandlerBase } from "../IonHandlerBase.sol";
import { UniswapFlashloanBalancerSwapHandler } from "../UniswapFlashloanBalancerSwapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "../BalancerFlashloanDirectMintHandler.sol";
import { UniswapFlashswapHandler } from "../UniswapFlashswapHandler.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @notice Handler for the ETHx collateral.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EthXHandler is
    UniswapFlashloanBalancerSwapHandler,
    UniswapFlashswapHandler,
    BalancerFlashloanDirectMintHandler
{
    using StaderLibrary for IStaderStakePoolsManager;

    // Stader deposit contract is separate from the ETHx lst contract
    IStaderStakePoolsManager public immutable STADER_DEPOSIT;

    /**
     * @notice Creates a new `EthXHandler` instance.
     * @param _ilkIndex of ETHx.
     * @param _ionPool `IonPool` contract address.
     * @param _gemJoin `GemJoin` contract address associated with ETHx.
     * @param _staderDeposit Address for the Stader deposit contract.
     * @param _whitelist Address of the `Whitelist` contract.
     * @param _wstEthUniswapPool Address of the WSTETH/ETH Uniswap V3 pool.
     * @param _ethXUniswapPool Address of the ETHx/ETH Uniswap V3 pool.
     * @param _balancerPoolId Balancer pool ID for the ETHx/ETH pool.
     */
    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        IStaderStakePoolsManager _staderDeposit,
        Whitelist _whitelist,
        IUniswapV3Pool _wstEthUniswapPool,
        IUniswapV3Pool _ethXUniswapPool,
        bytes32 _balancerPoolId
    )
        UniswapFlashloanBalancerSwapHandler(_wstEthUniswapPool, _balancerPoolId)
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
        UniswapFlashswapHandler(_ethXUniswapPool, false)
    {
        STADER_DEPOSIT = _staderDeposit;
    }

    /**
     * @notice Unwraps weth into eth and deposits into lst contract.
     * @dev Unwraps weth into eth and deposits into lst contract.
     * @param amountWeth The WETH amount to deposit. [WAD]
     * @return Amount of lst received. [WAD]
     */
    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        WETH.withdraw(amountWeth);
        return STADER_DEPOSIT.depositForLst(amountWeth);
    }

    /**
     * @notice Calculates the amount of eth required to receive `amountLst`.
     * @dev Calculates the amount of eth required to receive `amountLst`.
     * @param amountLst Desired output amount. [WAD]
     * @return Eth required for desired lst output. [WAD]
     */
    function _getEthAmountInForLstAmountOut(uint256 amountLst) internal view override returns (uint256) {
        return STADER_DEPOSIT.getEthAmountInForLstAmountOut(amountLst);
    }
}
