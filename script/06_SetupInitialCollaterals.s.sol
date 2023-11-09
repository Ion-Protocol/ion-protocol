// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";

import { BaseScript } from "script/Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

// TODO: Move to constants
address constant WST_ETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant MAINNET_ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
address constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;

uint8 constant STETH_ILK_INDEX = 0;
uint8 constant ETHX_ILK_INDEX = 1;
uint8 constant SWETH_ILK_INDEX = 2;

contract SetupInitialCollateralsScript is BaseScript {
    using StdJson for string;

    string configPath = "./deployment-config/06_SetupInitialCollaterals.json";
    string config = vm.readFile(configPath);

    function run() public broadcast {
        IonPool ionPool = IonPool(config.readAddress(".ionPool"));

        ionPool.initializeIlk(WST_ETH);
        ionPool.initializeIlk(MAINNET_ETHX);
        ionPool.initializeIlk(SWETH);

        SpotOracle wstEthSpot = SpotOracle(config.readAddress(".wstEthSpot"));
        SpotOracle ethXSpot = SpotOracle(config.readAddress(".ethXSpot"));
        SpotOracle swEthSpot = SpotOracle(config.readAddress(".swEthSpot"));

        ionPool.updateIlkSpot(STETH_ILK_INDEX, wstEthSpot);
        ionPool.updateIlkSpot(ETHX_ILK_INDEX, ethXSpot);
        ionPool.updateIlkSpot(SWETH_ILK_INDEX, swEthSpot);

        // TODO: Move debt ceilings to config
        ionPool.updateIlkDebtCeiling(STETH_ILK_INDEX, 100e45);
        ionPool.updateIlkDebtCeiling(ETHX_ILK_INDEX, 100e45);
        ionPool.updateIlkDebtCeiling(SWETH_ILK_INDEX, 100e45);
    }
}
