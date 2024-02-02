// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployWhitelistScript } from "../deploy/03_DeployWhitelist.s.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { Test } from "forge-std/Test.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployWhitelistTest is DeployTestBase, DeployWhitelistScript {
    function checkState(Whitelist whitelist) public {
        assert(address(whitelist).code.length > 0);
        assert(whitelist.lendersRoot() == lenderRoot);
        assert(whitelist.borrowersRoot(0) == borrowerRoots[0]);
        assert(whitelist.borrowersRoot(1) == INACTIVE);
        assert(whitelist.borrowersRoot(2) == INACTIVE);

        for (uint256 i = 0; i < protocolControlledAddresses.length; i++) {
            assert(whitelist.protocolWhitelist(protocolControlledAddresses[i]));
        }

        assert(whitelist.pendingOwner() == protocol);

        vm.startPrank(protocol);
        whitelist.acceptOwnership();
        vm.stopPrank();

        assert(whitelist.owner() == protocol);
        assert(whitelist.pendingOwner() == address(0));
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
