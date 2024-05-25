// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultFactory } from "./../../../src/vault/VaultFactory.sol";
import { CREATEX } from "./../../../src/Constants.sol";

import { DeployScript } from "./../../Deploy.s.sol";

// deploys to 0x0000000000d7dc416dfe993b0e3dd53ba3e27fc8
bytes32 constant SALT = 0x2f428c0d9f1d9e00034c85000000000000000000000000000000000000000000;

contract DeployVaultFactory is DeployScript {
    function run() public broadcast returns (VaultFactory vaultFactory) {
        bytes memory initCode = type(VaultFactory).creationCode;

        require(initCode.length > 0, "initCode");
        require(SALT != bytes32(0), "salt");

        vaultFactory = VaultFactory(CREATEX.deployCreate3(SALT, initCode));
    }
}
