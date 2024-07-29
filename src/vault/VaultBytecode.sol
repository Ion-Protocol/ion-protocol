// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { Vault } from "./Vault.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

/**
 * @title VaultBytecode
 * @author Molecular Labs
 * @notice The sole job of this contract is to deploy the embedded `Vault`
 * contract's bytecode with the constructor args. `VaultFactory` handles rest of
 * the verification and post-deployment logic.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract VaultBytecode {
    error OnlyFactory();

    address public constant VAULT_FACTORY = 0x0000000000D7DC416dFe993b0E3dd53BA3E27Fc8;

    /**
     * @notice Deploys the embedded `Vault` bytecode with the given constructor
     * args. Only the `VaultFactory` contract can call this function.
     * @dev This contract was separated from `VaultFactory` to reduce the
     * codesize of the factory contract.
     * @param baseAsset The asset that is being lent out to IonPools.
     * @param feeRecipient Address that receives the accrued manager fees.
     * @param feePercentage Fee percentage to be set.
     * @param name Name of the vault token.
     * @param symbol Symbol of the vault token.
     * @param initialDelay The initial delay for default admin transfers.
     * @param initialDefaultAdmin The initial default admin for the vault.
     * @param salt The salt used for CREATE2 deployment. The first 20 bytes must
     * be the msg.sender.
     * @param marketsArgs Arguments for the markets to be added to the vault.
     */
    function deploy(
        IERC20 baseAsset,
        address feeRecipient,
        uint256 feePercentage,
        string memory name,
        string memory symbol,
        uint48 initialDelay,
        address initialDefaultAdmin,
        bytes32 salt,
        Vault.MarketsArgs memory marketsArgs
    )
        external
        returns (Vault vault)
    {
        if (msg.sender != VAULT_FACTORY) revert OnlyFactory();

        vault = new Vault{ salt: salt }(
            baseAsset, feeRecipient, feePercentage, name, symbol, initialDelay, initialDefaultAdmin, marketsArgs
        );
    }
}
