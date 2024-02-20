// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { BaseScript } from "./Base.s.sol";
import { Liquidation } from "../src/Liquidation.sol";
import { WadRayMath } from "../src/libraries/math/WadRayMath.sol";
import { IonPool } from "../src/IonPool.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployLiquidationScript is BaseScript {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    string configPath = "./deployment-config/09_Liquidation.json";
    string config = vm.readFile(configPath);

    function run() public broadcast returns (Liquidation liquidation) {
        address ionPool = vm.parseJsonAddress(config, ".ionPool");
        address protocol = vm.parseJsonAddress(config, ".protocol");
        address reserveOracles = vm.parseJsonAddress(config, ".reserveOracle");
        uint256 liquidationThresholds = vm.parseJsonUint(config, ".liquidationThreshold");
        uint256 targetHealth = vm.parseJsonUint(config, ".targetHealth");
        uint256 reserveFactor = vm.parseJsonUint(config, ".reserveFactor");
        uint256 maxDiscounts = vm.parseJsonUint(config, ".maxDiscount");

        // TODO: after import constants
        // assert(reserveOracles.length == ILK_COUNT);
        // assert(liquidationThresholds.length == ILK_COUNT);
        // assert(maxDiscounts.length == ILK_COUNT);

        liquidation = new Liquidation{ salt: bytes32(abi.encode(0)) }(
            ionPool, protocol, reserveOracles, liquidationThresholds, targetHealth, reserveFactor, maxDiscounts
        );

        IonPool(ionPool).grantRole(IonPool(ionPool).LIQUIDATOR_ROLE(), address(liquidation));
    }
}
