// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";

import { BaseScript } from "../Base.s.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

address constant CREATE_CALL = 0xab6050062922Ed648422B44be36e33A3BebE8B3E; // sepolia
address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

contract PausePool is BaseScript, BatchScript {
    function run(bool send, IonPool ionPool) public broadcast {
        _validateInterface(ionPool);

        bytes memory pause = abi.encodeWithSelector(IonPool.pause.selector);

        addToBatch(address(ionPool), pause);

        executeBatch(SAFE, send);
    }
}

contract UnpausePool is BaseScript, BatchScript {
    function run(bool send, IonPool ionPool) public broadcast {
        _validateInterface(ionPool);

        bytes memory unpause = abi.encodeWithSelector(IonPool.unpause.selector);

        addToBatch(address(ionPool), unpause);

        executeBatch(SAFE, send);
    }
}

contract PauseGemJoin is BaseScript, BatchScript {
    function run(bool send, GemJoin gemJoin) public broadcast {
        _validateInterface(gemJoin);

        bytes memory pause = abi.encodeWithSelector(GemJoin.pause.selector, gemJoin);

        addToBatch(address(gemJoin), pause);

        executeBatch(SAFE, send);
    }
}

contract UnpauseGemJoin is BaseScript, BatchScript {
    function run(bool send, GemJoin gemJoin) public broadcast {
        bytes memory unpause = abi.encodeWithSelector(GemJoin.unpause.selector, gemJoin);

        addToBatch(address(gemJoin), unpause);

        executeBatch(SAFE, send);
    }
}

/**
 * @notice Assumes there is only one GemJoin 
 */
contract PauseSystem is BaseScript, BatchScript {
    function run(bool send, GemJoin gemJoin) public broadcast {
        _validateInterface(gemJoin);

        IonPool pool = IonPool(gemJoin.POOL());

        _validateInterface(pool);

        bytes memory pause = abi.encodeWithSelector(IonPool.pause.selector);

        // Both pause selectors are the same
        addToBatch(address(pool), pause);
        addToBatch(address(gemJoin), pause);

        executeBatch(SAFE, send);
    }
}

/**
 * @notice Assumes there is only one GemJoin 
 */
contract UnpauseSystem is BaseScript, BatchScript {
    function run(bool send, GemJoin gemJoin) public broadcast {
        _validateInterface(gemJoin);

        IonPool pool = IonPool(gemJoin.POOL());

        _validateInterface(pool);

        bytes memory unpause = abi.encodeWithSelector(IonPool.unpause.selector);

        // Both unpause selectors are the same
        addToBatch(address(pool), unpause);
        addToBatch(address(gemJoin), unpause);

        executeBatch(SAFE, send);
    }
}
