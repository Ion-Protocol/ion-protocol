// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

abstract contract DeployTestBase is Test {
    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"));
        vm.selectFork(mainnetFork);
    }
}
