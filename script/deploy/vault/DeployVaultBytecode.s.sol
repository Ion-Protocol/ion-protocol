// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultBytecode } from "./../../../src/vault/VaultBytecode.sol";
import { CREATEX } from "./../../../src/Constants.sol";

import { DeployScript } from "./../../Deploy.s.sol";

bytes32 constant SALT = 0xbcde1e1dd0bdb803514d8e000000000000000000000000000000000000000000;

contract DeployVaultBytecode is DeployScript {
    function run() public broadcast returns (VaultBytecode vaultBytecode) {
        bytes memory initCode = type(VaultBytecode).creationCode;

        require(initCode.length > 0, "initCode");
        require(SALT != bytes32(0), "salt");

        vaultBytecode = VaultBytecode(CREATEX.deployCreate3(SALT, initCode));
    }
}
