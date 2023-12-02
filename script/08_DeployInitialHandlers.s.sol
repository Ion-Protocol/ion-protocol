// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "../src/IonPool.sol";
import { WstEthHandler } from "../src/flash/handlers/WstEthHandler.sol";
import { EthXHandler } from "../src/flash/handlers/EthXHandler.sol";
import { SwEthHandler } from "../src/flash/handlers/SwEthHandler.sol";
import { IWstEth, IStaderStakePoolsManager, ISwEth } from "../src/interfaces/ProviderInterfaces.sol";
import { IWETH9 } from "../src/interfaces/IWETH9.sol";
import { GemJoin } from "../src/join/GemJoin.sol";
import { Whitelist } from "../src/Whitelist.sol";

import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import { BaseScript } from "./Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

// TODO: Move to interfaces. Also used in IonHandler_ForkBase
interface IComposableStableSwapPool {
    function getRate() external view returns (uint256);
}

uint8 constant STETH_ILK_INDEX = 0;
uint8 constant ETHX_ILK_INDEX = 1;
uint8 constant SWETH_ILK_INDEX = 2;

IWstEth constant MAINNET_WSTETH = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
IStaderStakePoolsManager constant MAINNET_STADER = IStaderStakePoolsManager(0xcf5EA1b38380f6aF39068375516Daf40Ed70D299);
ISwEth constant MAINNET_SWELL = ISwEth(0xf951E335afb289353dc249e82926178EaC7DEd78);

AggregatorV2V3Interface constant STETH_ETH_CHAINLINK =
    AggregatorV2V3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);
IComposableStableSwapPool constant STADER_POOL = IComposableStableSwapPool(0x37b18B10ce5635a84834b26095A0AE5639dCB752);
IUniswapV3Pool constant SWETH_ETH_POOL = IUniswapV3Pool(0x30eA22C879628514f1494d4BBFEF79D21A6B49A2);
uint24 constant SWETH_ETH_POOL_FEE = 500;

address constant MAINNET_ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;

IUniswapV3Factory constant FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

IUniswapV3Pool constant WSTETH_WETH_POOL = IUniswapV3Pool(0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa);
uint24 constant WSTETH_WETH_POOL_FEE = 100;

contract DeployInitialHandlersScript is BaseScript {
    using StdJson for string;

    string configPath = "./deployment-config/08_DeployInitialHandlers.json";
    string config = vm.readFile(configPath);

    function run()
        public
        broadcast
        returns (WstEthHandler wstEthHandler, EthXHandler ethXHandler, SwEthHandler swEthHandler)
    {
        IonPool ionPool = IonPool(config.readAddress(".ionPool"));
        GemJoin wstEthGemJoin = GemJoin(config.readAddress(".wstEthGemJoin"));
        GemJoin ethXGemJoin = GemJoin(config.readAddress(".ethXGemJoin"));
        GemJoin swEthGemJoin = GemJoin(config.readAddress(".swEthGemJoin"));
        Whitelist whitelist = Whitelist(config.readAddress(".whitelist"));

        wstEthHandler = new WstEthHandler(
                STETH_ILK_INDEX,
                ionPool,
                wstEthGemJoin,
                whitelist,
                FACTORY,
                WSTETH_WETH_POOL,
                WSTETH_WETH_POOL_FEE
            );
        ethXHandler = new EthXHandler(
                ETHX_ILK_INDEX,
                ionPool,
                ethXGemJoin,
                MAINNET_STADER,
                whitelist,
                WSTETH_WETH_POOL
            );
        swEthHandler = new SwEthHandler(
                SWETH_ILK_INDEX,
                ionPool,
                swEthGemJoin,
                whitelist,
                FACTORY,
                SWETH_ETH_POOL,
                SWETH_ETH_POOL_FEE
            );
    }
}
