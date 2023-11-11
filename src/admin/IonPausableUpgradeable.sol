// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/**
 * @dev A copy of OpenZeppelin's `Pausable` module but with an array of pause
 * booleans as opposed to one. This will allow for a more granular pausing set
 * up.
 *
 * `IonPool` will require three types of pausing. One pause is for halting
 * actions that put the protocol into a further unsafe state (e.g. borrows,
 * withdraws of base), one for pausing actions that put the protocol into a
 * safer state (e.g. repays, deposits of base), and one for pausing the accrual
 * of interest rates. Depnding on the situation, it may be desirable to pause
 * one, two, or all of these, hence the reasoning for this design.
 */
abstract contract IonPausableUpgradeable is ContextUpgradeable {
    enum Pauses {
        UNSAFE,
        SAFE
    }

    struct IonPausableStorage {
        // Initialized to unpaused implicitly
        bool[2] _pausedStates;
    }

    // keccak256(abi.encode(uint256(keccak256("ion.storage.IonPausable")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 private constant IonPausableStorageLocation =
        0x48c3e72c7d0b1210a7962d468cc626eef9908fe8b8be51a049f423a1848bb700;

    function _getIonPausableStorage() private pure returns (IonPausableStorage storage $) {
        assembly {
            $.slot := IonPausableStorageLocation
        }
    }

    error EnforcedPause(Pauses pauseIndex);
    error ExpectedPause(Pauses pauseIndex);

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(Pauses indexed pauseIndex, address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(Pauses indexed pauseIndex, address account);

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused(Pauses pauseIndex) {
        _requireNotPaused(pauseIndex);
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused(Pauses pauseIndex) {
        _requirePaused(pauseIndex);
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused(Pauses pauseIndex) public view virtual returns (bool) {
        IonPausableStorage storage $ = _getIonPausableStorage();
        return $._pausedStates[uint256(pauseIndex)];
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused(Pauses pauseIndex) internal view virtual {
        if (paused(pauseIndex)) revert EnforcedPause(pauseIndex);
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused(Pauses pauseIndex) internal view virtual {
        if (!paused(pauseIndex)) revert ExpectedPause(pauseIndex);
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause(Pauses pauseIndex) internal virtual whenNotPaused(pauseIndex) {
        IonPausableStorage storage $ = _getIonPausableStorage();
        $._pausedStates[uint256(pauseIndex)] = true;
        emit Paused(pauseIndex, _msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause(Pauses pauseIndex) internal virtual whenPaused(pauseIndex) {
        IonPausableStorage storage $ = _getIonPausableStorage();
        $._pausedStates[uint256(pauseIndex)] = false;
        emit Unpaused(pauseIndex, _msgSender());
    }
}
