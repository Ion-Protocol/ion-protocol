// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Liquidation } from "../../src/Liquidation.sol";
import { IonPool } from "../../src/IonPool.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployLiquidationScript } from "../deploy/09_DeployLiquidation.s.sol";

contract DeployLiquidationTest is DeployTestBase, DeployLiquidationScript {
    function checkState(Liquidation liquidation) public {
        assertGt(address(liquidation).code.length, 0, "liquidation code");
        assertEq(liquidation.TARGET_HEALTH(), targetHealth, "targetHealth");
        assertEq(liquidation.BASE_DISCOUNT(), reserveFactor, "baseDiscount");

        assertEq(liquidation.MAX_DISCOUNT_0(), maxDiscount, "maxDiscount");

        assertEq(liquidation.LIQUIDATION_THRESHOLD_0(), liquidationThreshold, "liquidationThreshold");

        assertEq(liquidation.RESERVE_ORACLE_0(), reserveOracle, "reserveOracles");

        assertEq(liquidation.PROTOCOL(), protocol, "protocol");

        assertEq(address(liquidation.POOL()), address(ionPool), "ionPool");
        assertEq(address(liquidation.UNDERLYING()), address(IonPool(liquidation.POOL()).underlying()), "underlying");

        assertTrue(ionPool.hasRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation)), "liquidator role");
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
