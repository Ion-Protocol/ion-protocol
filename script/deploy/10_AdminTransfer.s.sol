// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";
import { IonPool } from "../../src/IonPool.sol";
import { YieldOracle } from "../../src/YieldOracle.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { Liquidation } from "../../src/Liquidation.sol";
import { ProxyAdmin } from "../../src/admin/ProxyAdmin.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

uint32 constant ILK_COUNT = 1;

contract AdminTransferScript is DeployScript {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    string configPath = "./deployment-config/10_AdminTransfer.json";
    string config = vm.readFile(configPath);

    IonPool ionPool = IonPool(config.readAddress(".ionPool"));
    YieldOracle yieldOracle = YieldOracle(config.readAddress(".yieldOracle"));
    Whitelist whitelist = Whitelist(config.readAddress(".whitelist"));
    ProxyAdmin proxyAdmin = ProxyAdmin(config.readAddress(".proxyAdmin"));
    Liquidation liquidation = Liquidation(config.readAddress(".liquidation"));
    GemJoin gemJoin = GemJoin(config.readAddress(".gemJoin"));

    function run() public broadcast {
        require(address(protocol) != address(0), "protocol address");

        _validateInterface(yieldOracle);
        _validateInterface(whitelist);
        _validateInterfaceIonPool(ionPool);

        require(proxyAdmin.owner() == initialDefaultAdmin, "proxy admin owner");

        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));
        ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(gemJoin));

        // Move the default admin role to the protocol
        // 1. initialDefaultAdmin calls beginDefaultAdminTransfer
        // 2. protocol calls acceptDefaultAdminTransfer()
        // Can't begin and accept atomically in the same block

        ionPool.beginDefaultAdminTransfer(protocol);
        // yieldOracle.transferOwnership(protocol);
        // whitelist.transferOwnership(protocol);
        proxyAdmin.transferOwnership(protocol);
    }
}
