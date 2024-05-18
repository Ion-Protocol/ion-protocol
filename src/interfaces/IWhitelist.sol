// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IWhitelist {
    error NotWhitelistedBorrower(uint8 ilkIndex, address addr);
    error NotWhitelistedLender(address addr);
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function acceptOwnership() external;
    function approveProtocolWhitelist(address addr) external;
    function borrowersRoot(uint8 ilkIndex) external view returns (bytes32);
    function isWhitelistedBorrower(
        uint8 ilkIndex,
        address poolCaller,
        address addr,
        bytes32[] memory proof
    )
        external
        view
        returns (bool);
    function isWhitelistedLender(
        address poolCaller,
        address addr,
        bytes32[] memory proof
    )
        external
        view
        returns (bool);
    function lendersRoot() external view returns (bytes32);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function protocolWhitelist(address protocolControlledAddress) external view returns (bool);
    function renounceOwnership() external;
    function revokeProtocolWhitelist(address addr) external;
    function transferOwnership(address newOwner) external;
    function updateBorrowersRoot(uint8 ilkIndex, bytes32 _borrowersRoot) external;
    function updateLendersRoot(bytes32 _lendersRoot) external;
}
