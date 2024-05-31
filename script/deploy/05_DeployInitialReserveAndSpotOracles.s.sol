// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { RAY } from "../../src/libraries/math/WadRayMath.sol";
import { EzEthWethReserveOracle } from "./../../src/oracles/reserve/lrt/EzEthWethReserveOracle.sol";
import { EzEthWethSpotOracle } from "./../../src/oracles/spot/lrt/EzEthWethSpotOracle.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployInitialReserveAndSpotOraclesScript is DeployScript {
    using StdJson for string;

    string configPath = "./deployment-config/05_DeployInitialReserveAndSpotOracles.json";
    string config = vm.readFile(configPath);

    uint256 maxChange = config.readUint(".maxChange");
    uint256 ltv = config.readUint(".ltv");

    function run() public broadcast returns (address reserveOracle, address spotOracle) {
        require(maxChange > 0.01e27, "maxChange must be greater than 1%");
        require(maxChange < RAY, "maxChange must be less than 100%");

        require(ltv > 0.2e27, "ltv must be greater than 20%");
        require(ltv < RAY, "ltv must be less than 100%");

        // Specific to using Redstone Oracles
        uint256 maxTimeFromLastUpdate = config.readUint(".maxTimeFromLastUpdate");

        if (deployCreate2) {
            reserveOracle = address(new EzEthWethReserveOracle{ salt: DEFAULT_SALT }(0, new address[](3), 0, maxChange));
            spotOracle = address(
                new EzEthWethSpotOracle{ salt: DEFAULT_SALT }(ltv, address(reserveOracle), maxTimeFromLastUpdate)
            );
        } else {
            reserveOracle = address(new EzEthWethReserveOracle(0, new address[](3), 0, maxChange));
            spotOracle = address(new EzEthWethSpotOracle(ltv, address(reserveOracle), maxTimeFromLastUpdate));
        }
    }
}
