// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployHandlersScript } from "../deploy/08_DeployHandlers.s.sol";
import { IonHandlerBase } from "../../src/flash/IonHandlerBase.sol";

contract DeployHandlersTest is DeployTestBase, DeployHandlersScript {
    function checkState(IonHandlerBase handler) public {
        assertGt(address(handler).code.length, 0, "handler code");
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
