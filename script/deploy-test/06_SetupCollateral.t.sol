// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DeployTestBase } from "./00_DeployTestBase.t.sol";

import { SetupCollateralScript } from "../deploy/06_SetupCollateral.s.sol";

contract SetupCollateralTest is DeployTestBase, SetupCollateralScript {
    function checkState() public {
        assertEq(ionPool.ilkCount(), 1, "ilk count");
        assertEq(ionPool.getIlkIndex(ilkAddress), 0, "ilk index");
        assertEq(ionPool.getIlkAddress(0), ilkAddress, "get ilk address");
        assertTrue(ionPool.addressContains(ilkAddress), "address contains");

        assertEq(address(ionPool.spot(0)), address(spotOracle), "spot oracle");
        assertEq(ionPool.debtCeiling(0), debtCeiling, "debt ceiling");
        assertEq(ionPool.dust(0), dust, "dust");
    }

    function test_PreExecution() public {
        super.run();
        checkState();
    }
}
