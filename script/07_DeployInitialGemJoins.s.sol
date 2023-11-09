// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { GemJoin } from "src/join/GemJoin.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "script/Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

// TODO: Move to constants
address constant WST_ETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant MAINNET_ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
address constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;

uint8 constant STETH_ILK_INDEX = 0;
uint8 constant ETHX_ILK_INDEX = 1;
uint8 constant SWETH_ILK_INDEX = 2;

contract DeployInitialGemJoinsScript is BaseScript {
    using StdJson for string;

    string configPath = "./deployment-config/07_DeployInitialGemJoins.json";
    string config = vm.readFile(configPath);

    function run() public broadcast returns (GemJoin wstEthGemJoin, GemJoin ethXGemJoin, GemJoin swEthGemJoin) {
        IonPool ionPool = IonPool(config.readAddress(".ionPool"));
        address owner = config.readAddress(".owner");

        wstEthGemJoin = new GemJoin(ionPool, IERC20(WST_ETH), STETH_ILK_INDEX, owner);
        ethXGemJoin = new GemJoin(ionPool, IERC20(MAINNET_ETHX), ETHX_ILK_INDEX, owner);
        swEthGemJoin = new GemJoin(ionPool, IERC20(SWETH), SWETH_ILK_INDEX, owner);

        ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(wstEthGemJoin));
        ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(ethXGemJoin));
        ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(swEthGemJoin));
    }
}
