// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { Liquidation } from "../../src/Liquidation.sol";
import { WadRayMath, RAY } from "../../src/libraries/math/WadRayMath.sol";
import { IonPool } from "../../src/IonPool.sol";
import { CREATEX } from "../../src/Constants.sol";
import { ReserveOracle } from "../../src/oracles/reserve/ReserveOracle.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

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
    bytes32 salt = config.readBytes32(".salt");

    function run() public broadcast returns (Liquidation liquidation) {
        _validateInterface(ionPool);
        _validateInterface(ReserveOracle(reserveOracle));

        require(targetHealth >= RAY, "target health lower");
        require(targetHealth < 1.5e27, "target health upper");

        require(liquidationThreshold < RAY, "liquidation threshold upper");
        require(liquidationThreshold > 0.5e27, "liquidation threshold lower");

        require(maxDiscount < 0.3e27, "max discount upper");

        // Reserve factor is actually BASE_DISCOUNT
        require(reserveFactor < maxDiscount, "reserve factor upper");

        // NOTE: Liquidation contract reads the ilkCount() of the IonPool which
        // should always be 1.
        require(ionPool.ilkCount() == ILK_COUNT, "ionPool ilk count");

        bytes memory initCode = type(Liquidation).creationCode;

        liquidation = Liquidation(
            CREATEX.deployCreate3(
                salt,
                abi.encodePacked(
                    initCode,
                    abi.encode(
                        address(ionPool),
                        protocol,
                        reserveOracle,
                        liquidationThreshold,
                        targetHealth,
                        reserveFactor,
                        maxDiscount
                    )
                )
            )
        );

        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));
    }
}
