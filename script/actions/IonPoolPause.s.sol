// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { BaseScript } from "../Base.s.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

import { console2 } from "forge-std/console2.sol";

import { InterestRate, IlkData } from "../../src/InterestRate.sol";
import { CreateCall } from "./util/CreateCall.sol";

address constant CREATE_CALL = 0xab6050062922Ed648422B44be36e33A3BebE8B3E; // sepolia
address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

contract Pause is BaseScript, BatchScript {
    function run(bytes32 _mode) public {
        console2.logBytes32(_mode);
        if (_mode == "test") {
            console2.log("test");
        } else if (_mode == "prod") {
            console2.log("prod");
        }
        address ionPool = 0x3faAcB959664ae4556FFD46C1950275d8905e232;

        bytes memory pause = abi.encodeWithSelector(IonPool.pause.selector);

        addToBatch(ionPool, pause);

        executeBatch(SAFE, true);
    }
}

contract Unpause is BaseScript, BatchScript {
    function run(bool _send) public {
        address ionPool = 0x3faAcB959664ae4556FFD46C1950275d8905e232;

        bytes memory unpause = abi.encodeWithSelector(IonPool.unpause.selector);

        addToBatch(ionPool, unpause);

        executeBatch(SAFE, _send);
    }
}
