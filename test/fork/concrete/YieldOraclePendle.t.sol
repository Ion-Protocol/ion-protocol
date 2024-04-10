// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { YieldOraclePendle } from "../../../src/YieldOraclePendle.sol";
import { PT_WEETH_POOL, PT_RSWETH_POOL, PT_RSETH_POOL } from "../../../src/Constants.sol";

import { Test } from "forge-std/Test.sol";

contract YieldOraclePendle_Test is Test {
    YieldOraclePendle public oracle;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        // PT_WEETH_POOL.increaseObservationsCardinalityNext(1000);
        oracle = new YieldOraclePendle(PT_RSETH_POOL, 1800);
    }

    function test_apys() public {
        assertEq(oracle.apys(0), 0);
    }
}
