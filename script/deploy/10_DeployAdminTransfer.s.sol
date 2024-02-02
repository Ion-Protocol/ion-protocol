// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { BaseScript } from "../Base.s.sol";
import { Liquidation } from "../../src/Liquidation.sol";
import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";
import { IonPool } from "../../src/IonPool.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { console2 } from "forge-std/console2.sol";

uint32 constant ILK_COUNT = 1;

contract DeployAdminTransferScript is BaseScript {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    string defaultConfigPath = "./deployment-config/00_Default.json";
    string defaultConfig = vm.readFile(defaultConfigPath);

    string configPath = "./deployment-config/10_DeployAdminTransfer.json";
    string config = vm.readFile(configPath);

    address defaultAdmin = defaultConfig.readAddress(".defaultAdmin");
    address protocol = defaultConfig.readAddress(".protocol");
    IonPool ionPool = IonPool(config.readAddress(".ionPool"));

    function run() public broadcast {
        require(address(ionPool) != address(0), "ionPool address");
        require(address(protocol) != address(0), "protocol address");

        // Move the default admin role to the protocol
        // 1. initialDefaultAdmin calls beginDefaultAdminTransfer
        // 2. protocol calls acceptDefaultAdminTransfer()
        // Can't begin and accept atomically in the same block

        ionPool.beginDefaultAdminTransfer(protocol);
    }
}
