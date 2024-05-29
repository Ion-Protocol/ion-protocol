// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IGemJoin {
    error AddressEmptyCode(address target);
    error AddressInsufficientBalance(address account);
    error EnforcedPause();
    error ExpectedPause();
    error FailedInnerCall();
    error Int256Overflow();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error SafeERC20FailedOperation(address token);
    error WrongIlkAddress(uint8 ilkIndex, address gem);

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    function GEM() external view returns (address);
    function ILK_INDEX() external view returns (uint8);
    function POOL() external view returns (address);
    function acceptOwnership() external;
    function exit(address user, uint256 amount) external;
    function join(address user, uint256 amount) external;
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function pendingOwner() external view returns (address);
    function renounceOwnership() external;
    function totalGem() external view returns (uint256);
    function transferOwnership(address newOwner) external;
    function unpause() external;
}
