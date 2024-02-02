// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { WEETH_ADDRESS } from "../../src/Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "../Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

// TODO: Move to constants

contract DeployInitialGemJoinsScript is BaseScript {
    using StdJson for string;

    string defaultConfigPath = "./deployment-config/00_Default.json";
    string defaultConfig = vm.readFile(defaultConfigPath);

    string configPath = "./deployment-config/07_DeployInitialGemJoins.json";
    string config = vm.readFile(configPath);

    address ilkAddress = defaultConfig.readAddress(".ilkAddress");

    IonPool ionPool = IonPool(config.readAddress(".ionPool"));
    address defaultAdmin = defaultConfig.readAddress(".defaultAdmin");

    function run() public broadcast returns (GemJoin gemJoin) 
    // GemJoin wstEthGemJoin,
    // GemJoin ethXGemJoin,
    // GemJoin swEthGemJoin
    {
        gemJoin = new GemJoin(ionPool, IERC20(ilkAddress), 0, defaultAdmin);

        ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(gemJoin));

        // wstEthGemJoin = new GemJoin(ionPool, IERC20(WST_ETH), STETH_ILK_INDEX, owner);
        // ethXGemJoin = new GemJoin(ionPool, IERC20(MAINNET_ETHX), ETHX_ILK_INDEX, owner);
        // swEthGemJoin = new GemJoin(ionPool, IERC20(SWETH), SWETH_ILK_INDEX, owner);

        // ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(wstEthGemJoin));
        // ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(ethXGemJoin));
        // ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(swEthGemJoin));
    }
}
