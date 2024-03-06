// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { YieldOracleNull } from "../../src/YieldOracleNull.sol";

import { DeployScript } from "../Deploy.s.sol";

contract DeployYieldOracleNull is DeployScript {
    function run() public broadcast returns (YieldOracleNull yieldOracle) {
        if (deployCreate2) {
            yieldOracle = new YieldOracleNull{ salt: DEFAULT_SALT }();
        } else {
            yieldOracle = new YieldOracleNull();
        }
    }
}
