// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { Liquidation } from "../../src/Liquidation.sol";
import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";
import { IonPool } from "../../src/IonPool.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { console2 } from "forge-std/console2.sol";

uint32 constant ILK_COUNT = 1;

contract DeployLiquidationScript is DeployScript {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    string configPath = "./deployment-config/09_DeployLiquidation.json";
    string config = vm.readFile(configPath);

    uint256 targetHealth = config.readUint(".targetHealth");
    uint256 liquidationThreshold = config.readUint(".liquidationThreshold");
    uint256 maxDiscount = config.readUint(".maxDiscount");
    uint256 reserveFactor = config.readUint(".reserveFactor");

    IonPool ionPool = IonPool(config.readAddress(".ionPool"));
    address reserveOracle = config.readAddress(".reserveOracle");

    function run() public broadcast returns (Liquidation liquidation) {
        // NOTE: Liquidation contract reads the ilkCount() of the IonPool which
        // should always be 1.
        require(ionPool.ilkCount() == ILK_COUNT, "ionPool ilk count");

        uint256[] memory liquidationThresholds = new uint256[](ILK_COUNT);
        uint256[] memory maxDiscounts = new uint256[](ILK_COUNT);
        address[] memory reserveOracles = new address[](ILK_COUNT);

        liquidationThresholds[0] = liquidationThreshold;
        maxDiscounts[0] = maxDiscount;
        reserveOracles[0] = reserveOracle;

        liquidation = new Liquidation{ salt: bytes32(abi.encode(0)) }(
            address(ionPool), protocol, reserveOracles, liquidationThresholds, targetHealth, reserveFactor, maxDiscounts
        );

        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));
    }
}
