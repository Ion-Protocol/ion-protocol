// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol"; 
import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { console2 } from "forge-std/console2.sol";


contract Whitelist is Ownable2Step {
    bytes32 public borrowersWhitelistMerkleRoot;
    bytes32 public lendersWhitelistMerkleRoot;

    uint256 private constant TRUE = 1;
    uint256 private constant FALSE = 2;
    mapping(address => uint256) public protocolWhitelist; // peripheral addresses that can bypass the merkle proof check

    // --- Errors ---

    error InvalidWhitelistMerkleProof();

    constructor(bytes32 _borrowersWhitelistMerkleRoot, bytes32 _lendersWhitelistMerkleRoot) Ownable(msg.sender) {
        borrowersWhitelistMerkleRoot = _borrowersWhitelistMerkleRoot;
        lendersWhitelistMerkleRoot = _lendersWhitelistMerkleRoot;
    }

    function updateBorrowersWhitelistMerkleRoot(bytes32 _borrowersWhitelistMerkleRoot) external onlyOwner returns (bytes32) {
        borrowersWhitelistMerkleRoot = _borrowersWhitelistMerkleRoot;
    }

    function updateLendersWhitelistMerkleRoot(bytes32 _lendersWhitelistMerkleRoot) external onlyOwner returns (bytes32) {
        lendersWhitelistMerkleRoot = _lendersWhitelistMerkleRoot;
    }

    function approveProtocolWhitelist(address _addr) onlyOwner external {
        protocolWhitelist[_addr] = TRUE;
    }

    function revokeProtocolWhitelist(address _addr) onlyOwner external {
        protocolWhitelist[_addr] = FALSE;
    }

    // @dev called by external modifiers to prove inclusion as a borrower
    // @returns true if the addr is part of the borrower whitelist or the protocol whitelist. False otherwise
    function isWhitelistedBorrower(bytes32[] calldata proof, address addr) external view returns (bool) {
        if (protocolWhitelist[addr] == TRUE) return true;
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        return MerkleProof.verify(proof, borrowersWhitelistMerkleRoot, leaf);
    }

    // @dev called by external modifiers to prove inclusion as a lender
    // @returns true if the addr is part of the whitelist, false otherwise
    function isWhitelistedLender(bytes32[] calldata proof, address addr) external view returns (bool) {
        console2.log("is whitelisted lender"); 
        if (protocolWhitelist[addr] == TRUE) return true;
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        return MerkleProof.verify(proof, lendersWhitelistMerkleRoot, leaf);
    }
}
