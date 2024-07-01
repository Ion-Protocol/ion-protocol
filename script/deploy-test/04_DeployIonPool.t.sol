// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IIonPool } from "../../src/interfaces/IIonPool.sol";
import { IonPool } from "../../src/IonPool.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployIonPoolScript } from "../deploy/04_DeployIonPool.s.sol";

address constant CREATEX_PUBLIC_KEY = 0x94544835Cf97c631f101c5f538787fE14E2E04f6;

contract DeployIonPoolTest is DeployTestBase, DeployIonPoolScript {
    function checkState(IonPool ionPool) public {
        address ionPoolAddr = address(ionPool);
        assertGt(ionPoolAddr.code.length, 0, "code");
        assertEq(ionPool.owner(), initialDefaultAdmin, "owner");
        assertEq(ionPool.defaultAdmin(), initialDefaultAdmin, "initial default admin");
        assertEq(address(ionPool.underlying()), underlying, "underlying");
        assertEq(ionPool.treasury(), treasury, "treasury");
        assertEq(ionPool.decimals(), 18, "decimals");
        assertEq(lens.interestRateModule(IIonPool(ionPoolAddr)), address(interestRateModule), "interest rate module");
        assertEq(lens.whitelist(IIonPool(ionPoolAddr)), address(whitelist), "whitelist");

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
        (, IonPool ionPool) = super.runWithoutBroadcast();
        vm.stopPrank();
        checkState(ionPool);
    }
}
