// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool_InvariantTest } from "./ActorManager.t.sol";

contract IonPool_Echidna is IonPool_InvariantTest {
    constructor() {
        setUp();
    }

    function supply(uint256 index, uint256 amount) external {
        manager.supply(index, amount);
    }
}
