// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../src/IonPool.sol";
import { GemJoin } from "../../../src/join/GemJoin.sol";

import { BaseScript } from "../../Base.s.sol";

import { BatchScript } from "forge-safe/BatchScript.sol";

address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

// contract GrantGemJoinRole is BaseScript, BatchScript {
//     function run(bool _send, GemJoin _gemJoin) public {

//         address whitelist = address(0);

//         bytes memory txData = abi.encodeWithSelector(
//             IonPool.grantRole.selector,
//             IonPool.GEM_JOIN_ROLE(),

//         );

//         addToBatch(whitelist, txData);
//         executeBatch(SAFE, _send);
//     }
// }
