// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { VaultFactory } from "./../../../../src/vault/VaultFactory.sol";
import { IVault } from "./../../../../src/interfaces/IVault.sol";
import { VaultSharedSetup } from "../../../helpers/VaultSharedSetup.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract VaultFactoryTest is VaultSharedSetup {
    VaultFactory factory;

    address internal owner = address(1);
    address internal feeRecipient = address(2);
    uint256 internal feePercentage = 0.02e27;
    IERC20 internal baseAsset = BASE_ASSET;
    string internal name = "Vault Token";
    string internal symbol = "VT";

    function setUp() public override {
        super.setUp();

        factory = new VaultFactory();
    }

    function test_CreateVault() public {
        bytes32 salt = keccak256("random salt");
        IVault vault = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );

        assertEq(VAULT_ADMIN, vault.defaultAdmin(), "owner");
        assertEq(feeRecipient, vault.feeRecipient(), "fee recipient");
        assertEq(address(baseAsset), address(vault.baseAsset()), "base asset");
        assertEq(address(ionLens), address(vault.ionLens()), "ion lens");
    }

    function test_CreateVault_Twice() public {
        bytes32 salt = keccak256("first random salt");
        IVault vault = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );

        bytes32 salt2 = keccak256("second random salt");
        IVault vault2 = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt2
        );

        assertEq(owner, vault.owner(), "owner");
        assertEq(feeRecipient, vault.feeRecipient(), "fee recipient");
        assertEq(address(baseAsset), address(vault.baseAsset()), "base asset");
        assertEq(address(ionLens), address(vault.ionLens()), "ion lens");

        assertEq(owner, vault2.owner(), "owner");
        assertEq(feeRecipient, vault2.feeRecipient(), "fee recipient");
        assertEq(address(baseAsset), address(vault2.baseAsset()), "base asset");
        assertEq(address(ionLens), address(vault2.ionLens()), "ion lens");
    }

    function test_Revert_CreateVault_SameSaltTwice() public {
        bytes32 salt = keccak256("random salt");
        IVault vault = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );

        vm.expectRevert();
        IVault vault2 = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );
    }
}
