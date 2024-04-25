// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { Vault } from "./Vault.sol";
import { IVault } from "./../interfaces/IVault.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IIonLens } from "./../interfaces/IIonLens.sol";

/**
 * @title Ion Lending Vault Factory
 * @author Molecular Labs
 * @notice Factory contract for deploying Ion Lending Vaults.
 */
contract VaultFactory {
    // --- Events ---

    event CreateVault(
        address indexed vault,
        address indexed caller,
        address indexed owner,
        address feeRecipient,
        IERC20 baseAsset,
        IIonLens ionLens,
        string name,
        string symbol,
        bytes32 salt
    );

    // --- External ---

    /**
     * @notice Deploys a new Ion Lending Vault.
     * @param owner Owner of the vault
     * @param feeRecipient Address that receives the accrued manager fees.
     * @param baseAsset The asset that is being lent out to IonPools.
     * @param ionLens The IonLens contract for querying data.
     * @param name Name of the vault token.
     * @param symbol Symbol of the vault token.
     * @param salt The salt used for CREATE2 deployment.
     */
    function createVault(
        address owner,
        address feeRecipient,
        IERC20 baseAsset,
        IIonLens ionLens,
        string memory name,
        string memory symbol,
        bytes32 salt
    )
        external
        returns (IVault vault)
    {
        vault = IVault(address(new Vault{ salt: salt }(owner, feeRecipient, baseAsset, ionLens, name, symbol)));

        emit CreateVault(address(vault), msg.sender, owner, feeRecipient, baseAsset, ionLens, name, symbol, salt);
    }
}
