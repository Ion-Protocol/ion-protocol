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
        address vault,
        IERC20 indexed baseAsset,
        address feeRecipient,
        uint256 feePercentage,
        string name,
        string symbol,
        address indexed initialDefaultAdmin
    );

    // --- External ---

    /**
     * @notice Deploys a new Ion Lending Vault.
     * @param ionLens The IonLens contract for querying data.
     * @param baseAsset The asset that is being lent out to IonPools.
     * @param feeRecipient Address that receives the accrued manager fees.
     * @param feePercentage Fee percentage to be set.
     * @param name Name of the vault token.
     * @param symbol Symbol of the vault token.
     * @param initialDelay The initial delay for default admin transfers.
     * @param initialDefaultAdmin The initial default admin for the vault.
     * @param salt The salt used for CREATE2 deployment.
     */
    function createVault(
        IIonLens ionLens,
        IERC20 baseAsset,
        address feeRecipient,
        uint256 feePercentage,
        string memory name,
        string memory symbol,
        uint48 initialDelay,
        address initialDefaultAdmin,
        bytes32 salt
    )
        external
        returns (IVault vault)
    {
        vault = IVault(
            address(
                new Vault{ salt: salt }(
                    ionLens, baseAsset, feeRecipient, feePercentage, name, symbol, initialDelay, initialDefaultAdmin
                )
            )
        );

        emit CreateVault(address(vault), baseAsset, feeRecipient, feePercentage, name, symbol, initialDefaultAdmin);
    }
}
