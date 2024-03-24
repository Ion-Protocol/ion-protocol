// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../src/IonPool.sol";

import { BaseScript } from "../../Base.s.sol";

import { BatchScript } from "forge-safe/BatchScript.sol";

address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

contract UpdateDebtCeiling is BaseScript, BatchScript {
    function run(bool _send, IonPool ionPool, uint256 newDebtCeiling) public {
        require(newDebtCeiling == 0 || newDebtCeiling >= 1e45, "debt ceiling is nominated in RAD");

        // _validateInterface(ionPool);

        bytes memory txData = abi.encodeWithSelector(
            IonPool.updateIlkDebtCeiling.selector,
            0, // ilkIndex
            newDebtCeiling
        );

        addToBatch(address(ionPool), txData);
        executeBatch(SAFE, _send);
    }
}
