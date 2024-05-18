// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonLens } from "../../src/periphery/IonLens.sol";

import { Test } from "forge-std/Test.sol";

abstract contract DeployTestBase is Test {
    IonLens public lens;

    function setUp() public {
        uint256 mainnetFork = vm.createFork(vm.envString("DEPLOY_TEST_RPC_URL"));
        vm.selectFork(mainnetFork);
        lens = new IonLens();
    }
}
