// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { AdminTransferScript } from "../deploy/10_AdminTransfer.s.sol";

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

contract DeployAdminTransferTest is DeployTestBase, AdminTransferScript {
    function checkState() public {
        // pending admin transfer
        assertEq(ionPool.defaultAdmin(), initialDefaultAdmin, "default admin");

        (address newAdmin, uint48 addressSchedule) = ionPool.pendingDefaultAdmin();
        assertEq(newAdmin, protocol, "pending default admin");
        assertLe(addressSchedule, block.timestamp, "address schedule");

        // assertEq(yieldOracle.pendingOwner(), protocol, "yield oracle pending owner");
        assertEq(whitelist.pendingOwner(), protocol, "whitelist pending owner");
        assertEq(proxyAdmin.pendingOwner(), protocol, "proxy admin pending owner");
        assertTrue(ionPool.hasRole(ionPool.GEM_JOIN_ROLE(), address(gemJoin)), "gem join role");
        assertTrue(ionPool.hasRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation)), "gem join role");

        vm.warp(block.timestamp + 1);
        // accepting the transfer
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
