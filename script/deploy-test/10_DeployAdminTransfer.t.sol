// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployAdminTransferScript } from "../deploy/10_DeployAdminTransfer.s.sol";
import { console2 } from "forge-std/console2.sol";

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

contract DeployAdminTransferTest is DeployTestBase, DeployAdminTransferScript {
    function checkState() public {
        // pending admin transfer
        assertEq(ionPool.defaultAdmin(), initialDefaultAdmin, "default admin");

        (address newAdmin, uint48 addressSchedule) = ionPool.pendingDefaultAdmin();
        assertEq(newAdmin, protocol, "pending default admin");
        assertLe(addressSchedule, block.timestamp, "address schedule");

        console2.log("block.timestamp: ", block.timestamp);
        console2.log("delay: ", ionPool.defaultAdminDelay());

        vm.warp(block.timestamp + 1);
        // accepting the transferd
        vm.startPrank(protocol);
        ionPool.acceptDefaultAdminTransfer();
        vm.stopPrank();

        // pending admin is zero, previous holder has no role, new holder has role
        (address newAdminPostTransfer,) = ionPool.pendingDefaultAdmin();
        assertEq(newAdminPostTransfer, address(0), "pending default admin");
        assertEq(ionPool.defaultAdmin(), protocol, "new default admin");
        assertEq(ionPool.hasRole(DEFAULT_ADMIN_ROLE, protocol), true, "new admin role");
        assertEq(ionPool.hasRole(DEFAULT_ADMIN_ROLE, initialDefaultAdmin), false, "reset previous admin role");
    }

    function test_PreExecution() public {
        super.run();
        checkState();
    }
}
