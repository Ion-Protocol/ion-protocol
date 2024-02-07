// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";

import { BaseScript } from "../Base.s.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

address constant CREATE_CALL = 0xab6050062922Ed648422B44be36e33A3BebE8B3E; // sepolia
address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

contract PausePool is BaseScript, BatchScript {
    function run(bool send) public broadcast {
        address ionPool = 0x3faAcB959664ae4556FFD46C1950275d8905e232;

        bytes memory pause = abi.encodeWithSelector(IonPool.pause.selector);

        addToBatch(ionPool, pause);

        executeBatch(SAFE, send);
    }
}

contract UnpausePool is BaseScript, BatchScript {
    function run(bool send) public broadcast {
        address ionPool = 0x3faAcB959664ae4556FFD46C1950275d8905e232;

        bytes memory unpause = abi.encodeWithSelector(IonPool.unpause.selector);

        addToBatch(ionPool, unpause);

        executeBatch(SAFE, send);
    }
}

contract PauseGemJoin is BaseScript, BatchScript {
    function run(bool send, address gemJoin) public broadcast {
        bytes memory pause = abi.encodeWithSelector(GemJoin.pause.selector, gemJoin);

        require(gemJoin.code.length > 0, "No code at gemJoin address");

        addToBatch(gemJoin, pause);

        executeBatch(SAFE, send);
    }
}

contract UnpauseGemJoin is BaseScript, BatchScript {
    function run(bool send, address gemJoin) public broadcast {
        bytes memory unpause = abi.encodeWithSelector(GemJoin.unpause.selector, gemJoin);

        require(gemJoin.code.length > 0, "No code at gemJoin address");

        addToBatch(gemJoin, unpause);

        executeBatch(SAFE, send);
    }
}

// Going to assume here there is only one GemJoin

contract PauseSystem is BaseScript, BatchScript {
    function run(bool send, address gemJoin) public broadcast {
        bytes memory pause = abi.encodeWithSelector(IonPool.pause.selector);

        addToBatch(CREATE_CALL, pause);

        executeBatch(SAFE, send);
    }
}

contract UnpauseSystem is BaseScript, BatchScript {
    function run(bool send, address gemJoin) public broadcast {
        bytes memory unpause = abi.encodeWithSelector(IonPool.unpause.selector);

        addToBatch(CREATE_CALL, unpause);

        executeBatch(SAFE, send);
    }
}
