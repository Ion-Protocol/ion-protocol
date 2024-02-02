// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ReserveOracle } from "../../src/oracles/reserve/ReserveOracle.sol";
import { SpotOracle } from "../../src/oracles/spot/SpotOracle.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployIonPoolScript } from "../deploy/04_DeployIonPool.s.sol";

import { DeployInitialCollateralsSetUpScript } from "../deploy/06_DeployInitialCollateralsSetUp.s.sol";
import { WadRayMath, RAY } from "../../src/libraries/math/WadRayMath.sol";

import { Test } from "forge-std/Test.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployInitialCollateralsSetUpTest is DeployTestBase, DeployInitialCollateralsSetUpScript {
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
