// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import { IWETH9 } from "./interfaces/IWETH9.sol";
import {
    IWstEth,
    IStEth,
    IStaderStakePoolsManager,
    IETHx,
    ISwEth,
    IEEth,
    IWeEth,
    IRsEth,
    IRswEth,
    ILRTOracle,
    ILRTConfig,
    IEtherFiLiquidityPool,
    ILRTDepositPool,
    IEzEth,
    IRenzoOracle,
    IRestakeManager
} from "./interfaces/ProviderInterfaces.sol";
import { IWETH9 } from "./interfaces/IWETH9.sol";
import { IRedstonePriceFeed } from "./interfaces/IRedstone.sol";
import { IChainlink } from "./interfaces/IChainlink.sol";
import { ICreateX } from "./interfaces/ICreateX.sol";

import { IPMarketV3 } from "pendle-core-v2-public/interfaces/IPMarketV3.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IPool} from "./interfaces/aerodrome/IPool.sol";

uint8 constant REDSTONE_DECIMALS = 8;

address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

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
IChainlink constant BASE_WEETH_ETH_PRICE_CHAINLINK = IChainlink(0xFC1415403EbB0c693f9a7844b92aD2Ff24775C65);
IChainlink constant BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK = IChainlink(0x35e9D7001819Ea3B39Da906aE6b06A62cfe2c181);

// rsETH
IRedstonePriceFeed constant REDSTONE_RSETH_ETH_PRICE_FEED =
    IRedstonePriceFeed(0xA736eAe8805dDeFFba40cAB8c99bCB309dEaBd9B);
IRsEth constant RSETH = IRsEth(0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7);
IRsEth constant BASE_RSETH = IRsEth(0xEDfa23602D0EC14714057867A78d01e94176BEA0);
ILRTOracle constant RSETH_LRT_ORACLE = ILRTOracle(0x349A73444b1a310BAe67ef67973022020d70020d);
ILRTConfig constant RSETH_LRT_CONFIG = ILRTConfig(0x947Cb49334e6571ccBFEF1f1f1178d8469D65ec7);
ILRTDepositPool constant RSETH_LRT_DEPOSIT_POOL = ILRTDepositPool(0x036676389e48133B63a802f8635AD39E752D375D);
IPool constant BASE_RSETH_WETH_AERODROME = IPool(0xA24382874A6FD59de45BbccFa160488647514c28);

// rswETH
IRedstonePriceFeed constant REDSTONE_RSWETH_ETH_PRICE_FEED =
    IRedstonePriceFeed(0x3A236F67Fce401D87D7215695235e201966576E4);
IRswEth constant RSWETH = IRswEth(0xFAe103DC9cf190eD75350761e95403b7b8aFa6c0);

// ezETH
IRedstonePriceFeed constant REDSTONE_EZETH_ETH_PRICE_FEED =
    IRedstonePriceFeed(0xF4a3e183F59D2599ee3DF213ff78b1B3b1923696);
IEzEth constant EZETH = IEzEth(0xbf5495Efe5DB9ce00f80364C8B423567e58d2110);
IEzEth constant BASE_EZETH = IEzEth(0x2416092f143378750bb29b79eD961ab195CcEea5);
IRenzoOracle constant RENZO_ORACLE = IRenzoOracle(0x5a12796f7e7EBbbc8a402667d266d2e65A814042);
IRestakeManager constant RENZO_RESTAKE_MANAGER = IRestakeManager(0x74a09653A083691711cF8215a6ab074BB4e99ef5);
IPool constant BASE_EZTETH_WETH_AERODROME = IPool(0x0C8bF3cb3E1f951B284EF14aa95444be86a33E2f);

// Chainlink
IChainlink constant ETH_PER_STETH_CHAINLINK = IChainlink(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);
IChainlink constant MAINNET_USD_PER_ETH_CHAINLINK = IChainlink(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
IChainlink constant BASE_EZETH_ETH_PRICE_CHAINLINK = IChainlink(0x960BDD1dFD20d7c98fa482D793C3dedD73A113a3);
// will add address once rseth/eth feed is live on base, for now use ezeth/eth feed
IChainlink constant BASE_RSETH_ETH_PRICE_CHAINLINK = IChainlink(0x960BDD1dFD20d7c98fa482D793C3dedD73A113a3);
// Redstone
IRedstonePriceFeed constant MAINNET_USD_PER_ETHX_REDSTONE =
    IRedstonePriceFeed(0xFaBEb1474C2Ab34838081BFdDcE4132f640E7D2d);

// Uniswap
IUniswapV3Pool constant MAINNET_SWETH_ETH_UNISWAP_01 = IUniswapV3Pool(0x30eA22C879628514f1494d4BBFEF79D21A6B49A2);
IUniswapV3Pool constant MAINNET_WSTETH_WETH_UNISWAP = IUniswapV3Pool(0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa);

// Balancer
bytes32 constant EZETH_WETH_BALANCER_POOL_ID = 0x596192bb6e41802428ac943d2f1476c1af25cc0e000000000000000000000659;
bytes32 constant BASE_EZETH_WETH_BALANCER_POOL_ID = 0x0000000000000000000000000000000000000000000000000000000000000000;

// Pendle Pools
IPMarketV3 constant PT_WEETH_POOL = IPMarketV3(0xF32e58F92e60f4b0A37A69b95d642A471365EAe8);
IPMarketV3 constant PT_RSETH_POOL = IPMarketV3(0x4f43c77872Db6BA177c270986CD30c3381AF37Ee);
IPMarketV3 constant PT_EZETH_POOL = IPMarketV3(0xDe715330043799D7a80249660d1e6b61eB3713B3);
IPMarketV3 constant PT_RSWETH_POOL = IPMarketV3(0x1729981345aa5CaCdc19eA9eeffea90cF1c6e28b);

// CreateX
ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

// --- BASE ---

// EtherFi
bytes32 constant BASE_WEETH_WETH_BALANCER_POOL_ID = 0xab99a3e856deb448ed99713dfce62f937e2d4d74000000000000000000000118;
IUniswapV3Pool constant BASE_WSTETH_WETH_UNISWAP = IUniswapV3Pool(0x20E068D76f9E90b90604500B84c7e19dCB923e7e);
IChainlink constant BASE_SEQUENCER_UPTIME_FEED = IChainlink(0xBCF85224fc0756B9Fa45aA7892530B47e10b6433);
IERC20 constant BASE_WEETH = IERC20(0x04C0599Ae5A44757c0af6F9eC3b93da8976c150A);
IWETH9 constant BASE_WETH = IWETH9(0x4200000000000000000000000000000000000006);
