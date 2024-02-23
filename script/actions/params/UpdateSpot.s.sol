// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../src/IonPool.sol";
import { SpotOracle } from "../../../src/oracles/spot/SpotOracle.sol";

import { BaseScript } from "../../Base.s.sol";

import { BatchScript } from "forge-safe/BatchScript.sol";

address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

contract UpdateSpot is BaseScript, BatchScript {
    function run(bool _send, IonPool ionPool, SpotOracle newSpot) public {
        _validateInterface(ionPool);
        _validateInterface(newSpot);

        bytes memory txData = abi.encodeWithSelector(
            IonPool.updateIlkSpot.selector,
            0, // ilkIndex
            newSpot
        );

        addToBatch(address(ionPool), txData);
        executeBatch(SAFE, _send);
    }
}
