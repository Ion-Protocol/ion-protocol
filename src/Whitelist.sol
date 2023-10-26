// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract Whitelist is Ownable2Step {
    bytes32 public borrowersWhitelistMerkleRoot;
    bytes32 public lendersWhitelistMerkleRoot;

    mapping(address => bool) public protocolWhitelist; // peripheral addresses that can bypass the merkle proof check

    // --- Errors ---

    error InvalidWhitelistMerkleProof();

    constructor(bytes32 _borrowersWhitelistMerkleRoot, bytes32 _lendersWhitelistMerkleRoot) Ownable(msg.sender) {
        borrowersWhitelistMerkleRoot = _borrowersWhitelistMerkleRoot;
        lendersWhitelistMerkleRoot = _lendersWhitelistMerkleRoot;
    }

    function updateBorrowersWhitelistMerkleRoot(bytes32 _borrowersWhitelistMerkleRoot) external onlyOwner {
        borrowersWhitelistMerkleRoot = _borrowersWhitelistMerkleRoot;
    }

    function updateLendersWhitelistMerkleRoot(bytes32 _lendersWhitelistMerkleRoot) external onlyOwner {
        lendersWhitelistMerkleRoot = _lendersWhitelistMerkleRoot;
    }

    function approveProtocolWhitelist(address _addr) external onlyOwner {
        protocolWhitelist[_addr] = true;
    }

    function revokeProtocolWhitelist(address _addr) external onlyOwner {
        protocolWhitelist[_addr] = false;
    }

    /**
     * @dev called by external modifiers to prove inclusion as a borrower
     * @return true if the addr is part of the borrower whitelist or the protocol whitelist. False otherwise
     */
    function isWhitelistedBorrower(bytes32[] calldata proof, address addr) external view returns (bool) {
        if (protocolWhitelist[addr]) return true;
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        return MerkleProof.verify(proof, borrowersWhitelistMerkleRoot, leaf);
    }

    /**
     * @dev called by external modifiers to prove inclusion as a lender
     * @return true if the addr is part of the lender whitelist or the protocol whitelist. False otherwise
     */
    function isWhitelistedLender(bytes32[] calldata proof, address addr) external view returns (bool) {
        if (protocolWhitelist[addr]) return true;
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        return MerkleProof.verify(proof, lendersWhitelistMerkleRoot, leaf);
    }
}
