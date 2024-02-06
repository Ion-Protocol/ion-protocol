// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LOOK_BACK, YieldOracle } from "../../src/YieldOracle.sol";
import { DeployYieldOracleScript } from "../deploy/01_DeployYieldOracle.s.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { Test } from "forge-std/Test.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployYieldOracleTest is DeployTestBase, DeployYieldOracleScript {
    function checkState(YieldOracle yieldOracle) public view {
        require(address(yieldOracle).code.length > 0);
        for (uint256 i = 0; i < LOOK_BACK; i++) {
            // NOTE: the first buffer gets overwritten on deployment,
            // effectively means that today's rate takes up two days.
            if (i != 0) {
                require(weEthRates[i] == yieldOracle.historicalExchangeRates(i, 0));
            }
        }
    }

    function test_PreExecution() public {
        super.configureDeployment();
        checkState(super.run());
    }
}
