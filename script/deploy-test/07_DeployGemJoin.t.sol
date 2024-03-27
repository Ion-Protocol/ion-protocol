// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GemJoin } from "../../src/join/GemJoin.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployGemJoinScript } from "../deploy/07_DeployGemJoin.s.sol";

contract DeployGemJoinTest is DeployTestBase, DeployGemJoinScript {
    function checkState(GemJoin gemJoin) public {
        assertGt(address(gemJoin).code.length, 0, "gem join code");

        assertEq(address(gemJoin.GEM()), ilkAddress, "gem");
        assertEq(address(gemJoin.POOL()), address(ionPool), "pool");
        assertEq(gemJoin.ILK_INDEX(), 0, "ilk index");
        assertEq(gemJoin.totalGem(), 0, "total gem");
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
