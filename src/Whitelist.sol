// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract Whitelist {
    bytes32 public borrowersWhitelistMerkleRoot;
    bytes32 public lendersWhitelistMerkleRoot;

    // errors

    error InvalidWhitelistMerkleProof();

    constructor(bytes32 _borrowersWhitelistMerkleRoot, bytes32 _lendersWhitelistMerkleRoot) {
        borrowersWhitelistMerkleRoot = _borrowersWhitelistMerkleRoot;
        lendersWhitelistMerkleRoot = _lendersWhitelistMerkleRoot;
    }

    function updateBorrowersWhitelistMerkleRoot(bytes32 _borrowersWhitelistMerkleRoot) external returns (bytes32) {
        borrowersWhitelistMerkleRoot = _borrowersWhitelistMerkleRoot;
    }

    function updateLendersWhitelistMerkleRoot(bytes32 _lendersWhitelistMerkleRoot) external returns (bytes32) {
        lendersWhitelistMerkleRoot = _lendersWhitelistMerkleRoot;
    }

    // @dev called by external modifiers to prove inclusion as a borrower
    // @returns true if the addr is part of the whitelist, false otherwise
    function isWhitelistedBorrower(bytes32[] calldata proof, address addr) external view returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        return MerkleProof.verify(proof, borrowersWhitelistMerkleRoot, leaf);
    }

    // @dev called by external modifiers to prove inclusion as a lender
    // @returns true if the addr is part of the whitelist, false otherwise
    function isWhitelistedLender(bytes32[] calldata proof, address addr) external view returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        MerkleProof.verify(proof, lendersWhitelistMerkleRoot, leaf);
    }

    // modifier onlyWhitelistedBorroweres(bytes32[] memory proof) {
    //     bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender))));
    //     if (!_verifyWhitelist(proof, leaf)) {
    //         revert InvalidWhitelistMerkleProof();
    //     }
    //     _;
    // }

    // modifier onlyWhitelistedLenders(bytes32[] memory proof) {

    // }
}
