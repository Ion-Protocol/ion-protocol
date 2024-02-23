// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../src/IonPool.sol";

import { BaseScript } from "../../Base.s.sol";

import { BatchScript } from "forge-safe/BatchScript.sol";

address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

contract UpdateSupplyCap is BaseScript, BatchScript {
    function run(bool _send, IonPool ionPool, address newSupplyCap) public {
        _validateInterface(ionPool);

        bytes memory txData = abi.encodeWithSelector(IonPool.updateSupplyCap.selector, newSupplyCap);

        addToBatch(address(ionPool), txData);
        executeBatch(SAFE, _send);
    }
}
