// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { Vault } from "./../../../../src/vault/Vault.sol";
import { VaultFactory } from "./../../../../src/vault/VaultFactory.sol";
import { VaultSharedSetup } from "../../../helpers/VaultSharedSetup.sol";
import { ERC20PresetMinterPauser } from "../../../helpers/ERC20PresetMinterPauser.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract VaultFactoryTest is VaultSharedSetup {
    VaultFactory factory;

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
        Vault vault = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );

        assertEq(VAULT_ADMIN, vault.defaultAdmin(), "default admin");
        assertEq(feeRecipient, vault.feeRecipient(), "fee recipient");
        assertEq(address(baseAsset), address(vault.baseAsset()), "base asset");
        assertEq(address(ionLens), address(vault.ionLens()), "ion lens");
    }

    function test_CreateVault_Twice() public {
        bytes32 salt = keccak256("first random salt");
        Vault vault = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );

        bytes32 salt2 = keccak256("second random salt");
        Vault vault2 = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt2
        );

        assertEq(VAULT_ADMIN, vault.defaultAdmin(), "default admin");
        assertEq(feeRecipient, vault.feeRecipient(), "fee recipient");
        assertEq(address(baseAsset), address(vault.baseAsset()), "base asset");
        assertEq(address(ionLens), address(vault.ionLens()), "ion lens");

        assertEq(VAULT_ADMIN, vault2.defaultAdmin(), "default admin");
        assertEq(feeRecipient, vault2.feeRecipient(), "fee recipient");
        assertEq(address(baseAsset), address(vault2.baseAsset()), "base asset");
        assertEq(address(ionLens), address(vault2.ionLens()), "ion lens");
    }

    function test_Revert_CreateVault_SameSaltTwice() public {
        bytes32 salt = keccak256("random salt");
        Vault vault = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );

        vm.expectRevert();
        Vault vault2 = factory.createVault(
            ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );
    }

    function test_CreateVault_SameSaltDifferentBytecode() public {
        bytes32 salt = keccak256("random salt");

        Vault vault = factory.createVault(
            ionLens, BASE_ASSET, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );

        IERC20 diffBaseAsset = IERC20(address(new ERC20PresetMinterPauser("Another Wrapped Staked ETH", "wstETH2")));

        Vault vault2 = factory.createVault(
            ionLens, diffBaseAsset, feeRecipient, feePercentage, name, symbol, INITIAL_DELAY, VAULT_ADMIN, salt
        );

        require(address(vault) != address(vault2), "different deployment address");
    }
}
