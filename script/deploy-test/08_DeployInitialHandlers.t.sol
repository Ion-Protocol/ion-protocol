// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployInitialHandlersScript } from "../deploy/08_DeployInitialHandlers.s.sol";
import { IonHandlerBase } from "../../src/flash/handlers/base/IonHandlerBase.sol";

contract DeployInitialHandlers is DeployTestBase, DeployInitialHandlersScript {
    function checkState(IonHandlerBase handler) public {
        assertGt(address(handler).code.length, 0, "handler code");
        // TODO: Test for UniswapDirectMintHandler
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
