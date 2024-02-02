// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployIonPoolScript } from "../deploy/04_DeployIonPool.s.sol";
import { Test } from "forge-std/Test.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployIonPoolTest is DeployTestBase, DeployIonPoolScript {
    function checkState(IonPool ionPool) public {
        assert(address(ionPool).code.length > 0);
        assert(ionPool.owner() == initialDefaultAdmin);
        assert(ionPool.defaultAdmin() == initialDefaultAdmin);
        assert(address(ionPool.underlying()) == underlying);
        assert(ionPool.treasury() == treasury);
        assert(ionPool.decimals() == 18);
        assert(ionPool.interestRateModule() == address(interestRateModule));
        assert(ionPool.whitelist() == address(whitelist));

        vm.startPrank(initialDefaultAdmin);
        ionPool.beginDefaultAdminTransfer(protocol);
        vm.stopPrank();

        // warp time past default admin transfer delay which is zero
        vm.warp(block.timestamp + 1);

        vm.startPrank(protocol);
        ionPool.acceptDefaultAdminTransfer();
        vm.stopPrank();

        assert(ionPool.owner() == protocol);
        assert(ionPool.defaultAdmin() == protocol);
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
