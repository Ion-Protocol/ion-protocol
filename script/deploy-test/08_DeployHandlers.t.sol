// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployHandlersScript } from "../deploy/08_DeployHandlers.s.sol";
import { IonHandlerBase } from "../../src/flash/IonHandlerBase.sol";

contract DeployHandlersTest is DeployTestBase, DeployHandlersScript {
    function checkState(IonHandlerBase handler) public {
        assertGt(address(handler).code.length, 0, "handler code");
        assertEq(address(ionPool.getIlkAddress(0)), address(handler.LST_TOKEN()));
        assertEq(address(ionPool.getIlkAddress(0)), ilkAddress);
        assertEq(address(ionPool.underlying()), address(handler.BASE()));
        assertEq(address(handler.JOIN().GEM()), address(handler.LST_TOKEN()));
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
