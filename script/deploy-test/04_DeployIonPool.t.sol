// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployIonPoolScript } from "../deploy/04_DeployIonPool.s.sol";
import { Test } from "forge-std/Test.sol";

import { console2 } from "forge-std/console2.sol";

address constant CREATEX_PUBLIC_KEY = 0x01bd9aBD70D74D8eC70D338bD6099ca29DA3F9B4;

contract DeployIonPoolTest is DeployTestBase, DeployIonPoolScript {
    function checkState(IonPool ionPool) public {
        assertGt(address(ionPool).code.length, 0, "code");
        assertEq(ionPool.owner(), initialDefaultAdmin, "owner");
        assertEq(ionPool.defaultAdmin(), initialDefaultAdmin, "initial default admin");
        assertEq(address(ionPool.underlying()), underlying, "underlying");
        assertEq(ionPool.treasury(), treasury, "treasury");
        assertEq(ionPool.decimals(), 18, "decimals");
        assertEq(ionPool.interestRateModule(), address(interestRateModule), "interest rate module");
        assertEq(ionPool.whitelist(), address(whitelist), "whitelist");

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
        vm.startPrank(CREATEX_PUBLIC_KEY);
        IonPool ionPool = super.runWithoutBroadcast();
        vm.stopPrank();
        console2.log(address(ionPool));
        checkState(ionPool);
    }
}
