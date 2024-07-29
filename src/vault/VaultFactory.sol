// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { VaultBytecode } from "./VaultBytecode.sol";
import { Vault } from "./Vault.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Ion Lending Vault Factory
 * @author Molecular Labs
 * @notice Factory contract for deploying Ion Lending Vaults.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract VaultFactory {
    using SafeERC20 for IERC20;

    // --- Errors ---

    error SaltMustBeginWithMsgSender();

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

    VaultBytecode public constant BYTECODE_DEPLOYER = VaultBytecode(0x0000000000382a154e4A696A8C895b4292fA3D82);

    // --- Modifier ---

    /**
     * @dev Guarantees msg.sender protection for salts. If another caller
     * frontruns a deployment transaction, the salt cannot be stolen.
     * Taken from 0age's `Create2Factory`.
     * https://github.com/0age/Pr000xy/blob/master/contracts/Create2Factory.sol
     * @param salt The salt used for CREATE2 deployment. The first 20 bytes must
     * be the msg.sender.
     */
    modifier containsCaller(bytes32 salt) {
        if (address(bytes20(salt)) != msg.sender) {
            revert SaltMustBeginWithMsgSender();
        }
        _;
    }

    // --- External ---

    /**
     * @notice Deploys a new Ion Lending Vault.
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
    function createVault(
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
        containsCaller(salt)
        returns (Vault vault)
    {
        vault = BYTECODE_DEPLOYER.deploy(
            baseAsset, feeRecipient, feePercentage, name, symbol, initialDelay, initialDefaultAdmin, salt, marketsArgs
        );

        emit CreateVault(address(vault), baseAsset, feeRecipient, feePercentage, name, symbol, initialDefaultAdmin);
    }
}
