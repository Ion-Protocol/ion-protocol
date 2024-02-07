// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../src/IonPool.sol";
import { BaseScript } from "../../Base.s.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

contract UpdateSpot is BaseScript, BatchScript {
    function run(bool _send, address newSpot) public {
        address ionPool = 0x3faAcB959664ae4556FFD46C1950275d8905e232;

        require(newSpot.code.length > 0, "No code at spot address");

        bytes memory txData = abi.encodeWithSelector(
            IonPool.updateIlkSpot.selector,
            0, // ilkIndex
            newSpot
        );

        addToBatch(ionPool, txData);
        executeBatch(SAFE, _send);
    }
}
