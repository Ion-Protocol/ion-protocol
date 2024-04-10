// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { YieldOraclePendle } from "../../../src/YieldOraclePendle.sol";
import { PT_RSETH_POOL } from "../../../src/Constants.sol";

import { Test } from "forge-std/Test.sol";

contract YieldOraclePendle_Test is Test {
    YieldOraclePendle public oracle;

    function test_apys() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_625_980);
        oracle = new YieldOraclePendle(PT_RSETH_POOL, 1800, 0.9e18);
        assertEq(oracle.apys(0), 42_260_965);
    }

    function test_apysYieldCeiling() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        // 2% is a low enough ceiling that it should always be hit
        oracle = new YieldOraclePendle(PT_RSETH_POOL, 1800, 0.02e18);
        assertEq(oracle.apys(0), 0.02e8);
    }
}
