// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool_InvariantTest } from "./ActorManager.t.sol";

contract IonPool_Echidna is IonPool_InvariantTest {
    constructor() {
        _setUp(false, false);
    }

    function fuzzedFallback(
        uint128 userIndex,
        uint128 ilkIndex,
        uint128 amount,
        uint128 warpTimeAmount,
        uint256 functionIndex
    )
        public
    {
        actorManager.fuzzedFallback(userIndex, ilkIndex, amount, warpTimeAmount, functionIndex);
    }
}
