// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployWhitelistScript } from "../deploy/03_DeployWhitelist.s.sol";
import { Whitelist } from "../../src/Whitelist.sol";

contract DeployWhitelistTest is DeployTestBase, DeployWhitelistScript {
    function checkState(Whitelist whitelist) public {
        assert(address(whitelist).code.length > 0);
        assertEq(whitelist.owner(), initialDefaultAdmin, "initial owner");
        assertEq(whitelist.lendersRoot(), lenderRoot, "lendersRoot");
        assertEq(whitelist.borrowersRoot(0), borrowerRoots[0], "borrowersRoot(0)");
        assertEq(whitelist.pendingOwner(), address(0), "pendingOwner should be zero");

        vm.startPrank(initialDefaultAdmin);
        whitelist.transferOwnership(protocol);
        vm.stopPrank();

        vm.startPrank(protocol);
        whitelist.acceptOwnership();
        vm.stopPrank();

        assertEq(whitelist.owner(), protocol, "owner");
        assertEq(whitelist.pendingOwner(), address(0), "pendingOwner");
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
