// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { GemJoin } from "src/join/GemJoin.sol";
import { IonHandlerBase } from "src/flash/handlers/base/IonHandlerBase.sol";
import { Whitelist } from "src/Whitelist.sol";
import { StaderLibrary } from "src/libraries/StaderLibrary.sol";
import { IStaderStakePoolsManager } from "src/interfaces/ProviderInterfaces.sol";
import { UniswapFlashloanBalancerSwapHandler } from "src/flash/handlers/base/UniswapFlashloanBalancerSwapHandler.sol";
import { BalancerFlashloanDirectMintHandler } from "src/flash/handlers/base/BalancerFlashloanDirectMintHandler.sol";

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
        IUniswapV3Pool _wstEthUniswapPool,
        bytes32 _balancerPoolId
    )
        UniswapFlashloanBalancerSwapHandler(_wstEthUniswapPool, _balancerPoolId)
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
