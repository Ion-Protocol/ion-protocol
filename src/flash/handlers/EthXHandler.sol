// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { GemJoin } from "../../join/GemJoin.sol";
import { IonHandlerBase } from "../../flash/handlers/base/IonHandlerBase.sol";
import { Whitelist } from "../../Whitelist.sol";
import { StaderLibrary } from "../../libraries/StaderLibrary.sol";
import { IStaderStakePoolsManager } from "../../interfaces/ProviderInterfaces.sol";
import { UniswapFlashloanBalancerSwapHandler } from "../../flash/handlers/base/UniswapFlashloanBalancerSwapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "../../flash/handlers/base/BalancerFlashloanDirectMintHandler.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @dev Since ETHx only has liquidity on Balancer, a free Balancer flashloan
 * cannot be used due to the reentrancy locks on the Balancer vault. Instead we
 * will take a cheap flashloan from the wstETH/ETH uniswap pool.
 */
contract EthXHandler is UniswapFlashloanBalancerSwapHandler, BalancerFlashloanDirectMintHandler {
    using StaderLibrary for IStaderStakePoolsManager;

    // Stader deposit contract is separate from the ETHx lst contract
    IStaderStakePoolsManager immutable STADER_DEPOSIT;

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        IStaderStakePoolsManager _staderDeposit,
        Whitelist _whitelist,
        IUniswapV3Pool _wstEthUniswapPool
    )
        UniswapFlashloanBalancerSwapHandler(_wstEthUniswapPool)
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
    {
        STADER_DEPOSIT = _staderDeposit;
    }

    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        WETH.withdraw(amountWeth);
        return STADER_DEPOSIT.depositForLst(amountWeth);
    }

    function _getEthAmountInForLstAmountOut(uint256 amountLst) internal view override returns (uint256) {
        return STADER_DEPOSIT.getEthAmountInForLstAmountOut(amountLst);
    }
}
