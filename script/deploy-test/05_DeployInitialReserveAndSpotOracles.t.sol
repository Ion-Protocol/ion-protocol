// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ReserveOracle } from "../../src/oracles/reserve/ReserveOracle.sol";
import { SpotOracle } from "../../src/oracles/spot/SpotOracle.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployInitialReserveAndSpotOraclesScript } from "../deploy/05_DeployInitialReserveAndSpotOracles.s.sol";

contract DeployInitialReserveAndSpotOraclesTest is DeployTestBase, DeployInitialReserveAndSpotOraclesScript {
    function checkState(ReserveOracle reserveOracle, SpotOracle spotOracle) public {
        assertGt(address(reserveOracle).code.length, 0, "reserve oracle code");
        assertEq(reserveOracle.ILK_INDEX(), 0, "reserve oracle ilk index");
        assertEq(reserveOracle.QUORUM(), 0, "reserve oracle quorum");
        assertEq(reserveOracle.MAX_CHANGE(), maxChange, "reserve oracle max change");
        assertGt(reserveOracle.getProtocolExchangeRate(), 0, "reserve oracle get protocol exchange rate");
        assertGt(reserveOracle.currentExchangeRate(), 0, "reserve oracle current exchange rate");

        assertGt(address(spotOracle).code.length, 0, "spot oracle code");
        assertEq(spotOracle.LTV(), ltv, "spot oracle ltv");
        assertEq(address(spotOracle.RESERVE_ORACLE()), address(reserveOracle), "spot oracle reserve oracle");
        assertGt(spotOracle.getPrice(), 0, "spot oracle get price");
        assertGt(spotOracle.getSpot(), 0, "spot oracle get spot");
    }

    function test_PreExecution() public {
        (address reserveOracle, address spotOracle) = super.run();
        checkState(ReserveOracle(reserveOracle), SpotOracle(spotOracle));
    }
}
