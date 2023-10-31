// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "forge-std/console2.sol";

contract Whitelist is Ownable2Step {
    mapping(address => bool) public protocolWhitelist; // peripheral addresses that can bypass the merkle proof check

    mapping(uint8 => bytes32) public borrowersRoot; // root of the merkle tree of borrowers for each ilk

    bytes32 public lendersRoot; // root of the merkle tree of lenders for each ilk

    // --- Errors ---

    error InvalidConstructorArguments();
    error InvalidWhitelistMerkleProof();
    error NotWhitelistedBorrower(uint8 ilkIndex, address addr);
    error NotWhitelistedLender(address addr);

    constructor(bytes32[] memory _borrowersRoots, bytes32 _lendersRoot) Ownable(msg.sender) {
        for (uint8 i = 0; i < _borrowersRoots.length; i++) {
            borrowersRoot[i] = _borrowersRoots[i];
        }
        lendersRoot = _lendersRoot;
    }

    function updateBorrowersRoot(uint8 ilkIndex, bytes32 _borrowersRoot) external onlyOwner {
        borrowersRoot[ilkIndex] = _borrowersRoot;
    }

    function updateLendersRoot(bytes32 _lendersRoot) external onlyOwner {
        lendersRoot = _lendersRoot;
    }

    function approveProtocolWhitelist(address addr) external onlyOwner {
        protocolWhitelist[addr] = true;
    }

    function revokeProtocolWhitelist(address addr) external onlyOwner {
        protocolWhitelist[addr] = false;
    }

    /**
     * @dev called by external modifiers to prove inclusion as a borrower
     * @return true if the addr is part of the borrower whitelist or the protocol whitelist. False otherwise
     */
    function isWhitelistedBorrower(
        uint8 ilkIndex,
        address addr,
        bytes32[] calldata proof
    )
        external
        view
        returns (bool)
    {
        if (protocolWhitelist[addr]) return true;
        bytes32 root = borrowersRoot[ilkIndex];
        if (root == 0) return true;
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        if (MerkleProof.verify(proof, root, leaf)) {
            return true;
        } else {
            revert NotWhitelistedBorrower(ilkIndex, addr);
        }
    }

    /**
     * @dev called by external modifiers to prove inclusion as a lender
     * @return true if the addr is part of the lender whitelist or the protocol whitelist. False otherwise
     */
    function isWhitelistedLender(address addr, bytes32[] calldata proof) external view returns (bool) {
        if (protocolWhitelist[addr]) return true;
        bytes32 root = lendersRoot;
        if (root == bytes32(0)) return true;
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        if (MerkleProof.verify(proof, root, leaf)) {
            return true;
        } else {
            revert NotWhitelistedLender(addr);
        }
    }
}
