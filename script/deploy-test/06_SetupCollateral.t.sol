// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IIonPool } from "../../src/interfaces/IIonPool.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";

import { SetupCollateralScript } from "../deploy/06_SetupCollateral.s.sol";

contract SetupCollateralTest is DeployTestBase, SetupCollateralScript {
    function checkState() public {
        IIonPool iIonPool = IIonPool(address(ionPool));
        assertEq(lens.ilkCount(iIonPool), 1, "ilk count");
        assertEq(lens.getIlkIndex(iIonPool, ilkAddress), 0, "ilk index");
        assertEq(ionPool.getIlkAddress(0), ilkAddress, "get ilk address");

        assertEq(address(lens.spot(iIonPool, 0)), address(spotOracle), "spot oracle");
        assertEq(lens.debtCeiling(iIonPool, 0), debtCeiling, "debt ceiling");
        assertEq(lens.dust(iIonPool, 0), dust, "dust");
    }

    function test_PreExecution() public {
        super.run();
        checkState();
    }
}
