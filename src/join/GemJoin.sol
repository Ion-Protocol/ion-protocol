// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import { IonPool } from "../IonPool.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice Collateral deposits are held independently from the `IonPool` core
 * contract, but credited to users through `gem` balances.
 * 
 * @dev Seperating collateral deposits from the core contract allows for
 * handling tokens with non-standard behavior, if needed.
 * 
 * This contract implements access control through `Ownable2Step`.
 * 
 * This contract implements pausing through OpenZeppelin's `Pausable`.
 * 
 * @custom:security-contact security@molecularlabs.io
 */
contract GemJoin is Ownable2Step, Pausable {
    error Int256Overflow();
    error WrongIlkAddress(uint8 ilkIndex, IERC20 gem);

    using SafeERC20 for IERC20;

    IERC20 public immutable GEM;
    IonPool public immutable POOL;
    uint8 public immutable ILK_INDEX;

    uint256 public totalGem;

    /**
     * @notice Creates a new `GemJoin` instance.
     * @param _pool Address of the `IonPool` contract.
     * @param _gem ERC20 collateral to be associated with this `GemJoin` instance.
     * @param _ilkIndex of the associated collateral.
     * @param owner Admin of the contract.
     */
    constructor(IonPool _pool, IERC20 _gem, uint8 _ilkIndex, address owner) Ownable(owner) {
        GEM = _gem;
        POOL = _pool;
        ILK_INDEX = _ilkIndex;

        // Sanity check
        if (_pool.getIlkAddress(_ilkIndex) != address(_gem)) revert WrongIlkAddress(_ilkIndex, _gem);
    }

    /**
     * @notice Pauses the contract.
     * @dev Pauses the contract.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev Unpauses the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Converts ERC20 token into gem (credit inside of the `IonPool`'s internal accounting).
     * @dev Gem will be sourced from `msg.sender` and credited to `user`.
     * @param user to credit the gem to.
     * @param amount of gem to add. [WAD]
     */
    function join(address user, uint256 amount) external whenNotPaused {
        if (int256(amount) < 0) revert Int256Overflow();

        totalGem += amount;

        POOL.mintAndBurnGem(ILK_INDEX, user, int256(amount));
        GEM.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Debits gem from the `IonPool`'s internal accounting and withdraws it into ERC20 token.
     * @dev Gem will be debited from `msg.sender` and sent to `user`.
     * @param user to send the withdrawn ERC20 tokens to.
     * @param amount of gem to remove. [WAD]
     */
    function exit(address user, uint256 amount) external whenNotPaused {
        if (int256(amount) < 0) revert Int256Overflow();

        totalGem -= amount;

        POOL.mintAndBurnGem(ILK_INDEX, msg.sender, -int256(amount));
        GEM.safeTransfer(user, amount);
    }
}
