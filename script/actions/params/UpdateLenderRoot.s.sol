// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Whitelist } from "../../../src/Whitelist.sol";
import { BaseScript } from "../../Base.s.sol";
import { BatchScript } from "forge-safe/BatchScript.sol";

address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

contract UpdateLenderRoot is BaseScript, BatchScript {
    function run(bool _send, bytes32 newRoot) public {
        address whitelist = address(0);

        bytes memory txData = abi.encodeWithSelector(Whitelist.updateLendersRoot.selector, newRoot);

        addToBatch(whitelist, txData);
        executeBatch(SAFE, _send);
    }
}
