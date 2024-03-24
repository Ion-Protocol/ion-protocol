// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonLens } from "../../../src/periphery/IonLens.sol";
import { IIonPool } from "../../../src/interfaces/IIonPool.sol";
import { IonPool } from "../../../src/IonPool.sol";

import { Test } from "forge-std/Test.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

contract IonLensTest is Test {
    IonLens public ionLens;
    IIonPool public ionPool = IIonPool(0x0000000000eaEbd95dAfcA37A39fd09745739b78);
    IonPool public updatedImpl;

    function setUp() public {
        // Pre-upgrade block
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_494_278);
        ionLens = new IonLens();
        updatedImpl = new IonPool();
    }

    function test_IlkCount() public {
        uint256 ilkCountBefore = ionPool.ilkCount();

        _updateImpl();

        uint256 ilkCountAfter = ionLens.ilkCount(ionPool);

        assertEq(ilkCountBefore, ilkCountAfter, "ilk count");
    }

    function _updateImpl() public {
        vm.store(
            address(ionPool),
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
            bytes32(uint256(uint160(address(updatedImpl))))
        );
    }
}
