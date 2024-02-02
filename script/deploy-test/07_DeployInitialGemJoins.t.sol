// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GemJoin } from "../../src/join/GemJoin.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployInitialGemJoinsScript } from "../deploy/07_DeployInitialGemJoins.s.sol";

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

contract DeployGemJoinTest is DeployTestBase, DeployInitialGemJoinsScript {
    function checkState(GemJoin gemJoin) public {
        assertGt(address(gemJoin).code.length, 0, "gem join code");
        assertTrue(ionPool.hasRole(ionPool.GEM_JOIN_ROLE(), address(gemJoin)), "gem join role");

        assertEq(address(gemJoin.GEM()), ilkAddress, "gem");
        assertEq(address(gemJoin.POOL()), address(ionPool), "pool");
        assertEq(gemJoin.ILK_INDEX(), 0, "ilk index");
        assertEq(gemJoin.totalGem(), 0, "total gem");
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
