// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { BaseScript } from "./Base.s.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { Liquidation } from "src/Liquidation.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";
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
        address[] memory reserveOracles = vm.parseJsonAddressArray(config, ".reserveOracles");
        uint256[] memory liquidationThresholds = vm.parseJsonUintArray(config, ".liquidationThresholds");
        uint256 targetHealth = vm.parseJsonUint(config, ".targetHealth");
        uint256 reserveFactor = vm.parseJsonUint(config, ".reserveFactor");
        uint256[] memory maxDiscounts = vm.parseJsonUintArray(config, ".maxDiscounts");

        // TODO: after import constants
        // assert(reserveOracles.length == ILK_COUNT);
        // assert(liquidationThresholds.length == ILK_COUNT);
        // assert(maxDiscounts.length == ILK_COUNT);

        liquidation = new Liquidation(
            ionPool, protocol, reserveOracles, liquidationThresholds, targetHealth, reserveFactor, maxDiscounts
        );
    }
}
