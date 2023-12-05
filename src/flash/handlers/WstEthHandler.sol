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

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract WstEthHandler is UniswapFlashswapHandler, BalancerFlashloanDirectMintHandler {
    using LidoLibrary for IWstEth;

    // TODO: this fails the non-fork test because it doesn't exist outside mainnet
    IERC20 constant STETH = IERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        GemJoin _gemJoin,
        Whitelist _whitelist,
        IUniswapV3Factory _factory,
        IUniswapV3Pool _wstEthUniswapPool,
        uint24 _poolFee
    )
        IonHandlerBase(_ilkIndex, _ionPool, _gemJoin, _whitelist)
        // token0 is wstEth
        UniswapFlashswapHandler(_factory, _wstEthUniswapPool, _poolFee, false)
    {
        // NOTE: approves wstEth contract infinite approval to move this contract's stEth
        STETH.approve(address(LST_TOKEN), type(uint256).max);
    }

    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        WETH.withdraw(amountWeth);
        return IWstEth(address(LST_TOKEN)).depositForLst(amountWeth);
    }

    function _getEthAmountInForLstAmountOut(uint256 amountLst) internal view override returns (uint256) {
        return IWstEth(address(LST_TOKEN)).getEthAmountInForLstAmountOut(amountLst);
    }

    function zapDepositAndBorrow(uint256 stEthAmount, uint256 amountToBorrow) external {
        STETH.transferFrom(msg.sender, address(this), stEthAmount);
        uint256 outputWstEthAmount = IWstEth(address(LST_TOKEN)).wrap(stEthAmount);
        _depositAndBorrow(msg.sender, msg.sender, outputWstEthAmount, amountToBorrow, AmountToBorrow.IS_MAX);
    }

    function zapFlashLeverageCollateral(
        uint256 initialStEthDeposit,
        uint256 resultingAdditionalStEthCollateral,
        uint256 maxResultingDebt
    )
        external
    {
        STETH.transferFrom(msg.sender, address(this), initialStEthDeposit);
        uint256 initialDepositWstEthAmount = IWstEth(address(LST_TOKEN)).wrap(initialStEthDeposit);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(LST_TOKEN)).getWstETHByStETH(resultingAdditionalStEthCollateral);
        _flashLeverageCollateral(initialDepositWstEthAmount, resultingAdditionalWstEthCollateral, maxResultingDebt);
    }

    function zapFlashLeverageWeth(
        uint256 initialStEthDeposit,
        uint256 resultingAdditionalStEthCollateral,
        uint256 maxResultingDebt
    )
        external
    {
        STETH.transferFrom(msg.sender, address(this), initialStEthDeposit);
        uint256 initialDepositWstEthAmount = IWstEth(address(LST_TOKEN)).wrap(initialStEthDeposit);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(LST_TOKEN)).getWstETHByStETH(resultingAdditionalStEthCollateral);
        _flashLeverageWeth(initialDepositWstEthAmount, resultingAdditionalWstEthCollateral, maxResultingDebt);
    }

    function zapFlashswapLeverage() external { }
}
