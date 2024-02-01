// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IWETH9 } from "./interfaces/IWETH9.sol";
import {
    IWstEth,
    IStEth,
    IStaderStakePoolsManager,
    IETHx,
    ISwEth,
    IEEth,
    IWeEth,
    IEtherFiLiquidityPool
} from "./interfaces/ProviderInterfaces.sol";
import { IRedstonePriceFeed } from "./interfaces/IRedstone.sol";

IWETH9 constant WETH_ADDRESS = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

// StETH
IWstEth constant WSTETH_ADDRESS = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
IStEth constant STETH_ADDRESS = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

// ETHx
IETHx constant ETHX_ADDRESS = IETHx(0xA35b1B31Ce002FBF2058D22F30f95D405200A15b);
IStaderStakePoolsManager constant STADER_STAKE_POOLS_MANAGER_ADDRESS =
    IStaderStakePoolsManager(0xcf5EA1b38380f6aF39068375516Daf40Ed70D299);

// swETH
ISwEth constant SWETH_ADDRESS = ISwEth(0xf951E335afb289353dc249e82926178EaC7DEd78);

// eETH
IEEth constant EETH_ADDRESS = IEEth(0x35fA164735182de50811E8e2E824cFb9B6118ac2);
IEtherFiLiquidityPool constant ETHER_FI_LIQUIDITY_POOL_ADDRESS =
    IEtherFiLiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);
IWeEth constant WEETH_ADDRESS = IWeEth(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
IRedstonePriceFeed constant REDSTONE_WEETH_ETH_PRICE_FEED =
    IRedstonePriceFeed(0x8751F736E94F6CD167e8C5B97E245680FbD9CC36);
