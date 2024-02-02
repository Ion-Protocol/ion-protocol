// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Errors } from "../../src/Errors.sol";
import { IonPool } from "../../src/IonPool.sol";
import { SpotOracle } from "../../src/oracles/spot/SpotOracle.sol";

import { BaseScript } from "../Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { WEETH_ADDRESS } from "../../src/Constants.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployInitialCollateralsSetUpScript is BaseScript, Errors {
    using StdJson for string;

    string configPath = "./deployment-config/06_DeployInitialCollateralsSetUp.json";
    string config = vm.readFile(configPath);

    string defaultConfigPath = "./deployment-config/00_Default.json";
    string defaultConfig = vm.readFile(defaultConfigPath);

    address ilkAddress = defaultConfig.readAddress(".ilkAddress");

    IonPool ionPool = IonPool(config.readAddress(".ionPool"));
    SpotOracle spotOracle = SpotOracle(config.readAddress(".spotOracle"));
    uint256 debtCeiling = config.readUint(".debtCeiling");
    uint256 dust = config.readUint(".dust");

    function run() public broadcast {
        // this deployer address needs to have the ION role.
        ionPool.initializeIlk(ilkAddress);
        ionPool.updateIlkSpot(0, spotOracle);
        ionPool.updateIlkDebtCeiling(0, debtCeiling);
        ionPool.updateIlkDust(0, dust);

        // ionPool.initializeIlk(WST_ETH);
        // ionPool.initializeIlk(MAINNET_ETHX);
        // ionPool.initializeIlk(SWETH);

        // SpotOracle wstEthSpot = SpotOracle(config.readAddress(".wstEthSpot"));
        // SpotOracle ethXSpot = SpotOracle(config.readAddress(".ethXSpot"));
        // SpotOracle swEthSpot = SpotOracle(config.readAddress(".swEthSpot"));

        // ionPool.updateIlkSpot(STETH_ILK_INDEX, wstEthSpot);
        // ionPool.updateIlkSpot(ETHX_ILK_INDEX, ethXSpot);
        // ionPool.updateIlkSpot(SWETH_ILK_INDEX, swEthSpot);

        // ionPool.updateIlkDebtCeiling(STETH_ILK_INDEX, 100e45);
        // ionPool.updateIlkDebtCeiling(ETHX_ILK_INDEX, 100e45);
        // ionPool.updateIlkDebtCeiling(SWETH_ILK_INDEX, 100e45);
    }
}
