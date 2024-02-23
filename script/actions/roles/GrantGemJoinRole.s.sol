// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../src/IonPool.sol";

import { BaseScript } from "../../Base.s.sol";

import { AccessControlDefaultAdminRulesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

import { BatchScript } from "forge-safe/BatchScript.sol";

address constant SAFE = 0xcecc1978A819D4A3c0A2ee7C260ECb7A10732EEF;

contract GrantGemJoinRole is BaseScript, BatchScript {
    function run(bool _send, IonPool ionPool, address roleReceiver) public {
        address whitelist = address(0);

        bytes memory txData = abi.encodeWithSelector(
            AccessControlDefaultAdminRulesUpgradeable.grantRole.selector, ionPool.GEM_JOIN_ROLE(), roleReceiver
        );

        addToBatch(whitelist, txData);
        executeBatch(SAFE, _send);
    }
}

contract RevokeGemJoinRole is BaseScript, BatchScript {
    function run(bool _send, IonPool ionPool, address roleReceiver) public {
        address whitelist = address(0);

        bytes memory txData = abi.encodeWithSelector(
            AccessControlDefaultAdminRulesUpgradeable.revokeRole.selector, ionPool.GEM_JOIN_ROLE(), roleReceiver
        );

        addToBatch(whitelist, txData);
        executeBatch(SAFE, _send);
    }
}
