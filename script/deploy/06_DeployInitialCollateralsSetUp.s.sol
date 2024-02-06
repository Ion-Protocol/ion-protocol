// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { IonPool } from "../../src/IonPool.sol";
import { SpotOracle } from "../../src/oracles/spot/SpotOracle.sol";

import { BaseScript } from "../Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { WEETH_ADDRESS } from "../../src/Constants.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployInitialCollateralsSetUpScript is DeployScript {
    using StdJson for string;

    string configPath = "./deployment-config/06_DeployInitialCollateralsSetUp.json";
    string config = vm.readFile(configPath);

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
    }
}
