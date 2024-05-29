// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { RAY } from "../../src/libraries/math/WadRayMath.sol";
import { SpotOracle } from "./../../src/oracles/spot/SpotOracle.sol";
import { WeEthWstEthSpotOracle } from "../../src/oracles/spot/lrt/WeEthWstEthSpotOracle.sol";
import { RsEthWstEthSpotOracle } from "./../../src/oracles/spot/lrt/RsEthWstEthSpotOracle.sol";
import { RswEthWstEthSpotOracle } from "./../../src/oracles/spot/lrt/RswEthWstEthSpotOracle.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { console2 } from "forge-std/console2.sol";

// NOTE ALWAYS CHECK WHETHER THE CORRECT CONTRACT IS BEING DEPLOYED
contract RedeploySpotOracleScript is DeployScript {
    using StdJson for string;

    string configPath = "./deployment-config/11_RedeploySpotOracle.json";
    string config = vm.readFile(configPath);

    uint256 ltv = config.readUint(".ltv");
    address reserveOracle = config.readAddress(".reserveOracle");

    function run() public broadcast returns (SpotOracle spotOracle) {
        require(ltv > 0.2e27, "ltv must be greater than 20%");
        require(ltv < RAY, "ltv must be less than 100%");

        // Specific to using Redstone Oracles
        uint256 maxTimeFromLastUpdate = config.readUint(".maxTimeFromLastUpdate");

        if (deployCreate2) {
            spotOracle =
                new RswEthWstEthSpotOracle{ salt: DEFAULT_SALT }(ltv, address(reserveOracle), maxTimeFromLastUpdate);
        } else {
            spotOracle = new RswEthWstEthSpotOracle(ltv, address(reserveOracle), maxTimeFromLastUpdate);
        }

        console2.log("address(spotOracle): ", address(spotOracle));
    }
}
