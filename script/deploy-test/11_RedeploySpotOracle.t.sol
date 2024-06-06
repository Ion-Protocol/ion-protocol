// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ReserveOracle } from "../../src/oracles/reserve/ReserveOracle.sol";
import { SpotOracle } from "../../src/oracles/spot/SpotOracle.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { RedeploySpotOracleScript } from "../deploy/11_RedeploySpotOracle.s.sol";

contract RedeploySpotOracleTest is DeployTestBase, RedeploySpotOracleScript {
    function checkState(SpotOracle spotOracle) public {
        assertGt(address(spotOracle).code.length, 0, "spot oracle code");
        assertEq(spotOracle.LTV(), ltv, "spot oracle ltv");
        assertEq(address(spotOracle.RESERVE_ORACLE()), address(reserveOracle), "spot oracle reserve oracle");
        assertGt(spotOracle.getPrice(), 0, "spot oracle get price");
        assertGt(spotOracle.getSpot(), 0, "spot oracle get spot");
    }

    function test_PreExecution() public {
        (SpotOracle spotOracle) = super.run();
        checkState(spotOracle);
    }
}
