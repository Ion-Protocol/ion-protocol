// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool_InvariantTest } from "./ActorManager.t.sol";

contract IonPool_Echidna is IonPool_InvariantTest {
    constructor() {
        _setUp(false);
    }

    function supply(uint8 index, uint88 amount) external {
        actorManager.supply(index, amount);
    }

    function withdraw(uint8 index, uint88 amount) external {
        actorManager.withdraw(index, amount);
    }

    function borrow(uint8 borrowerIndex, uint8 ilkIndex, uint128 amount) external {
        actorManager.borrow(borrowerIndex, ilkIndex, amount);
    }

    function repay(uint8 borrowerIndex, uint8 ilkIndex, uint128 amount) external {
        actorManager.repay(borrowerIndex, ilkIndex, amount);
    }

    function depositCollateral(uint8 borrowerIndex, uint8 ilkIndex, uint128 amount) external {
        actorManager.depositCollateral(borrowerIndex, ilkIndex, amount);
    }

    function withdrawCollateral(uint8 borrowerIndex, uint8 ilkIndex, uint128 amount) external {
        actorManager.withdrawCollateral(borrowerIndex, ilkIndex, amount);
    }

    function gemJoin(uint8 borrowerIndex, uint8 ilkIndex, uint128 amount) external {
        actorManager.gemJoin(borrowerIndex, ilkIndex, amount);
    }

    function gemExit(uint8 borrowerIndex, uint8 ilkIndex, uint128 amount) external {
        actorManager.gemExit(borrowerIndex, ilkIndex, amount);
    }
}
