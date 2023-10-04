// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IonPoolInvariantTest } from "./ActorManager.t.sol";

contract IonPoolEchidna is IonPoolInvariantTest {
    constructor() {
        setUp();
    }

    function supply(uint256 index, uint256 amount) external {
        manager.supply(index, amount);
    }
}
