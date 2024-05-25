// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Vault } from "./../../../src/vault/Vault.sol";
import { VaultFactory } from "./../../../src/vault/VaultFactory.sol";
import { IIonPool } from "./../../../src/interfaces/IIonPool.sol";
import { IonPool } from "./../../../src/IonPool.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { BaseScript } from "./../../Base.s.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

VaultFactory constant factory = VaultFactory(address(0));
/**
 * Always use the factory to deploy a vault.
 */

contract DeployVault is BaseScript {
    using EnumerableSet for EnumerableSet.AddressSet;
    using StdJson for string;
    using SafeCast for uint256;

    string configPath = "./deployment-config/vault/DeployVault.json";
    string config = vm.readFile(configPath);

    VaultFactory factory = VaultFactory(config.readAddress(".factory"));

    address baseAsset = config.readAddress(".baseAsset");

    address feeRecipient = config.readAddress(".feeRecipient");
    uint256 feePercentage = config.readUint(".feePercentage");

    string name = config.readString(".name");
    string symbol = config.readString(".symbol");

    uint48 initialDelay = config.readUint(".initialDelay").toUint48();
    address initialDefaultAdmin = config.readAddress(".initialDefaultAdmin");

    bytes32 salt = config.readBytes32(".salt");

    uint256 initialDeposit = config.readUint(".initialDeposit");

    address[] marketsToAdd = config.readAddressArray(".marketsToAdd");
    uint256[] allocationCaps = config.readUintArray(".allocationCaps");
    address[] supplyQueue = config.readAddressArray(".supplyQueue");
    address[] withdrawQueue = config.readAddressArray(".withdrawQueue");

    IIonPool public constant IDLE = IIonPool(address(uint160(uint256(keccak256("IDLE_ASSET_HOLDINGS")))));

    EnumerableSet.AddressSet marketsCheck;

    /**
     * Validate that the salt is msg.sender protected.
     */
    function _validateSalt(bytes32 salt) internal {
        if (address(bytes20(salt)) != broadcaster) {
            revert("Invalid Salt");
        }
    }

    /**
     * No duplicates. No zero addresses. IonPool Interface.
     */
    function _validateIonPoolArray(address[] memory ionPools) internal returns (IIonPool[] memory typedIonPools) {
        typedIonPools = new IIonPool[](ionPools.length);

        for (uint8 i = 0; i < ionPools.length; i++) {
            address pool = ionPools[i];

            require(pool != address(0), "zero address");

            marketsCheck.add(pool);

            // If not the IDLE address, then validate the IonPool interface.
            if (pool != address(IDLE)) {
                _validateInterfaceIonPool(IonPool(pool));
            }

            // Check for duplicates in this array
            if (i != ionPools.length - 1) {
                for (uint8 j = i + 1; j < ionPools.length; j++) {
                    require(ionPools[i] != ionPools[j], "duplicate");
                }
            }

            typedIonPools[i] = IIonPool(pool);
        }
    }

    function run() public broadcast returns (Vault vault) {
        require(baseAsset != address(0), "baseAsset");

        require(feeRecipient != address(0), "feeRecipient");
        require(feePercentage <= 0.2e27, "feePercentage");

        // require(initialDelay != 0, "initialDelay");
        require(initialDefaultAdmin != address(0), "initialDefaultAdmin");

        require(initialDeposit >= 1e3, "initialDeposit");
        require(IERC20(baseAsset).balanceOf(broadcaster) >= initialDeposit, "sender balance");
        // require(IERC20(baseAsset).allowance(broadcaster, address(factory)) >= initialDeposit, "sender allowance");

        if (IERC20(baseAsset).allowance(broadcaster, address(factory)) < initialDeposit) {
            IERC20(baseAsset).approve(address(factory), 1e9);
        }

        // The length of all the arrays must be the same.
        require(marketsToAdd.length > 0);
        require(allocationCaps.length > 0);
        require(supplyQueue.length > 0);
        require(withdrawQueue.length > 0);

        uint256 marketsLength = marketsToAdd.length;

        require(marketsToAdd.length == marketsLength, "array length");
        require(allocationCaps.length == marketsLength, "array length");
        require(supplyQueue.length == marketsLength, "array length");

        _validateSalt(salt);

        IIonPool[] memory typedMarketsToAdd = _validateIonPoolArray(marketsToAdd);
        IIonPool[] memory typedSupplyQueue = _validateIonPoolArray(supplyQueue);
        IIonPool[] memory typedWithdrawQueue = _validateIonPoolArray(withdrawQueue);

        // If the length of the `uniqueMarketsCheck` set is greater than 4, that
        // means not all of the IonPool arrays had the same set of markets.
        // `_validateIonPoolArray` must be called before this.
        require(marketsToAdd.length == marketsCheck.length(), "markets not consistent");

        Vault.MarketsArgs memory marketsArgs = Vault.MarketsArgs({
            marketsToAdd: typedMarketsToAdd,
            allocationCaps: allocationCaps,
            newSupplyQueue: typedSupplyQueue,
            newWithdrawQueue: typedWithdrawQueue
        });

        vault = factory.createVault(
            IERC20(baseAsset),
            feeRecipient,
            feePercentage,
            name,
            symbol,
            initialDelay,
            initialDefaultAdmin,
            salt,
            marketsArgs,
            initialDeposit
        );

        require(vault.feeRecipient() == feeRecipient, "feeRecipient");
        require(vault.feePercentage() == feePercentage, "feePercentage");
        require(vault.defaultAdminDelay() == initialDelay, "initialDelay");
        require(vault.defaultAdmin() == initialDefaultAdmin, "initialDefaultAdmin");
        for (uint8 i = 0; i < marketsLength; i++) {
            require(vault.supplyQueue(i) == typedSupplyQueue[i], "supplyQueue");
            require(vault.withdrawQueue(i) == typedWithdrawQueue[i], "withdrawQueue");
        }
        require(vault.supportedMarketsLength() == marketsLength, "supportedMarkets");
    }
}
