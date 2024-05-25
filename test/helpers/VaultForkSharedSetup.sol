// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultFactory } from "./../../../../src/vault/VaultFactory.sol";
import { VaultBytecode } from "./../../src/vault/VaultBytecode.sol";
import { Vault } from "./../../../../src/vault/Vault.sol";
import { IIonPool } from "./../../../../src/interfaces/IIonPool.sol";
import { IonLens } from "./../../../../src/periphery/IonLens.sol";
import { WSTETH_ADDRESS } from "./../../../../src/Constants.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import "forge-std/Test.sol";

using EnumerableSet for EnumerableSet.AddressSet;

contract VaultForkBase is Test {
    // Mainnet addresses
    IIonPool constant WEETH_IONPOOL = IIonPool(0x0000000000eaEbd95dAfcA37A39fd09745739b78);
    IIonPool constant RSETH_IONPOOL = IIonPool(0x0000000000E33e35EE6052fae87bfcFac61b1da9);
    IIonPool constant RSWETH_IONPOOL = IIonPool(0x00000000007C8105548f9d0eE081987378a6bE93);
    IonLens constant LENS = IonLens(0xe89AF12af000C4f76a57A3aD16ef8277a727DC81);
    IERC20 constant BASE_ASSET = WSTETH_ADDRESS;

    bytes32 constant ION_ROLE = 0x5ab1a5ffb29c47d95dec8c5f9ad49a551754822b51a3359ed1c21e2be24beefa;
    address VAULT_ADMIN = 0x0000000000417626Ef34D62C4DC189b021603f2F;

    // Test addresses
    IIonPool constant IDLE = IIonPool(address(uint160(uint256(keccak256("IDLE_ASSET_HOLDINGS")))));

    address constant FEE_RECIPIENT = address(1);
    address constant NULL = address(0);

    uint48 constant INITIAL_DELAY = 0;
    uint256 constant MIN_INITIAL_DEPOSIT = 1e3;
    uint256 constant DEFAULT_ALLO_CAO = type(uint128).max;

    IIonPool[] markets;
    IIonPool[] supplyQueue;
    IIonPool[] withdrawQueue;

    Vault.MarketsArgs marketsArgs;

    uint256[] allocationCaps;

    VaultBytecode bytecodeDeployer = VaultBytecode(0x0000000000382a154e4A696A8C895b4292fA3D82);
    VaultFactory factory = VaultFactory(0x0000000000D7DC416dFe993b0E3dd53BA3E27Fc8);
    Vault vault;

    uint256 internal forkBlock = 0;

    function updateSupplyCap(IIonPool pool, uint256 cap) internal {
        vm.startPrank(pool.defaultAdmin());
        pool.updateSupplyCap(cap);
        vm.stopPrank();
        assertEq(LENS.supplyCap(pool), cap, "supply cap update");
    }

    function setUp() public virtual {
        if (forkBlock == 0) vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"));
        else vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"), forkBlock);

        // The factory stores a constant address for `VaultBytecode`
        VaultBytecode _bytecodeDeployer = new VaultBytecode();
        VaultFactory _factory = new VaultFactory();

        vm.etch(address(bytecodeDeployer), address(_bytecodeDeployer).code);
        vm.etch(address(factory), address(_factory).code);

        markets.push(IDLE);
        markets.push(WEETH_IONPOOL);
        markets.push(RSETH_IONPOOL);
        markets.push(RSWETH_IONPOOL);

        allocationCaps.push(DEFAULT_ALLO_CAO);
        allocationCaps.push(DEFAULT_ALLO_CAO);
        allocationCaps.push(DEFAULT_ALLO_CAO);
        allocationCaps.push(DEFAULT_ALLO_CAO);

        supplyQueue.push(WEETH_IONPOOL);
        supplyQueue.push(RSETH_IONPOOL);
        supplyQueue.push(RSWETH_IONPOOL);
        supplyQueue.push(IDLE);

        withdrawQueue.push(IDLE);
        withdrawQueue.push(RSWETH_IONPOOL);
        withdrawQueue.push(RSETH_IONPOOL);
        withdrawQueue.push(WEETH_IONPOOL);

        marketsArgs.marketsToAdd = markets;
        marketsArgs.allocationCaps = allocationCaps;
        marketsArgs.newSupplyQueue = supplyQueue;
        marketsArgs.newWithdrawQueue = withdrawQueue;

        uint256 feePercentage = 0.02e27;

        bytes32 salt = bytes32(abi.encodePacked(address(this), keccak256("random salt")));

        deal(address(BASE_ASSET), address(this), MIN_INITIAL_DEPOSIT);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);
        vault = factory.createVault(
            BASE_ASSET,
            FEE_RECIPIENT,
            feePercentage,
            "Ion Vault Token",
            "IVT",
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );

        require(vault.supplyQueue(0) == WEETH_IONPOOL);
        require(vault.supplyQueue(1) == RSETH_IONPOOL);
        require(vault.supplyQueue(2) == RSWETH_IONPOOL);
        require(vault.supplyQueue(3) == IDLE);
    }
}
