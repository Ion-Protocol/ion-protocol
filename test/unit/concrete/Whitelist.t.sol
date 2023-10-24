// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Whitelist } from "src/Whitelist.sol";
import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract MockModifiers {
    Whitelist whitelist;

    error NotWhitelistedBorrower(address addr);
    error NotWhitelistedLender(address addr);

    constructor(address _whitelist) {
        whitelist = Whitelist(_whitelist);
    }

    modifier onlyWhitelistedBorrowers(bytes32[] memory proof) {
        if (!whitelist.isWhitelistedBorrower(proof, msg.sender)) {
            revert NotWhitelistedBorrower(msg.sender);
        }
        _;
    }

    modifier onlyWhitelistedLenders(bytes32[] memory proof) {
        if (!whitelist.isWhitelistedLender(proof, msg.sender)) {
            revert NotWhitelistedLender(msg.sender);
        }
        _;
    }

    function onlyBorrowersFunction(bytes32[] memory proof) external onlyWhitelistedBorrowers(proof) { }
    function onlyLendersFunction(bytes32[] memory proof) external onlyWhitelistedLenders(proof) { }
}

// contract MockProxyModifiers() public {
//     Whitelist whitelist;
//     constructor (address _whitelist) {
//         whitelist = Whitelist(_whitelist);
//     }
//     modifier onlyWhitelistedBorrowers(bytes32[] memory proof) {
//         whitelist.isWhitelistedBorrower(proof, msg.s);
//     }
//     modifier onlyWhitelistedLenders(bytes32[] memory proof) {
//         whitelist.isWhitelistedLender(proof, msg.sender);
//     }
//     function onlyBorrowersFunction() onlyWhitelistedBorrowers {

//     }
//     function onlyLendersFunction() onlyWhitelistedLenders {

//     }
// }

contract WhitelistTest is Test {
    Whitelist whitelist;

    function setUp() public {
        bytes32 borrowersWhitelistMerkleRoot = 0;
        bytes32 lendersWhitelistMerkleRoot = 0;

        whitelist = new Whitelist(borrowersWhitelistMerkleRoot, lendersWhitelistMerkleRoot);
    }

    function test_UpdateWhitelistMerkleRoots() public {
        bytes32 borrowersRoot = 0xa83c6a6e585f4631021a5b1197e6bb8e82861564dfa44a97c69df6975bd4ba02;
        bytes32 lendersRoot = 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11;

        whitelist.updateBorrowersWhitelistMerkleRoot(borrowersRoot);
        whitelist.updateLendersWhitelistMerkleRoot(lendersRoot);

        assertEq(whitelist.borrowersWhitelistMerkleRoot(), borrowersRoot, "update borrowers root");
        assertEq(whitelist.lendersWhitelistMerkleRoot(), lendersRoot, "update lenders root");
    }

    // --- Mock Tests ---

    function test_WhitelistMockBorrowerUninitializedMerkleRoot() public { }

    function test_WhitelistMockBorrowerModifiers() public {
        // generate merkle root
        // [["0x1111111111111111111111111111111111111111"],
        // ["0x2222222222222222222222222222222222222222"],
        // ["0x3333333333333333333333333333333333333333"]];
        // => 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11

        whitelist.updateBorrowersWhitelistMerkleRoot(0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11);

        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        vm.startPrank(0x1111111111111111111111111111111111111111);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192);
        proof[1] = bytes32(0xcef861ae49469220eac9703d1077fa45b0a3ae990e4a8a7d325472f93cbca30e);
        mockModifiers.onlyBorrowersFunction(proof);
        vm.stopPrank();
    }

    function test_WhitelistMockBorrowerInvalidProof() public {
        // generate merkle root
        // [["0x1111111111111111111111111111111111111111"],
        // ["0x2222222222222222222222222222222222222222"],
        // ["0x3333333333333333333333333333333333333333"]];
        // => 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11

        whitelist.updateBorrowersWhitelistMerkleRoot(0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11);

        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        // correct address
        address addr = 0x1111111111111111111111111111111111111111;
        vm.startPrank(addr);
        bytes32[] memory proof = new bytes32[](2);
        // but wrong proof
        proof[0] = bytes32(0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192);
        proof[1] = bytes32(0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192);
        vm.expectRevert(abi.encodeWithSelector(MockModifiers.NotWhitelistedBorrower.selector, addr));
        mockModifiers.onlyBorrowersFunction(proof);
        vm.stopPrank();
    }

    function test_WhitelistMockBorrowerInvalidAddress() public {
        // generate merkle root
        // [["0x1111111111111111111111111111111111111111"],
        // ["0x2222222222222222222222222222222222222222"],
        // ["0x3333333333333333333333333333333333333333"]];
        // => 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11

        whitelist.updateBorrowersWhitelistMerkleRoot(0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11);
        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        // wrong address
        address addr = 0x4444444444444444444444444444444444444444;
        vm.startPrank(addr);
        bytes32[] memory proof = new bytes32[](2);
        // valid proof for 0x111...
        proof[0] = bytes32(0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192);
        proof[1] = bytes32(0xcef861ae49469220eac9703d1077fa45b0a3ae990e4a8a7d325472f93cbca30e);
        vm.expectRevert(abi.encodeWithSelector(MockModifiers.NotWhitelistedBorrower.selector, addr));
        mockModifiers.onlyBorrowersFunction(proof);
        vm.stopPrank();
    }

    // --- Ion Pool ---

    // function test_IonPoolWhiteListValidProof() public {
    //     ionPool.borrow()
    // }

    // --- Flash Leverage ---
    // flash leverage should forward the msg.sender to the merkle tree as sender

    // function test_WhitelistValidProof() public {

    //     // generate merkle root
    //     // leaves:
    //     // ["0x1111111111111111111111111111111111111111"],
    //     // ["0x2222222222222222222222222222222222222222"],
    //     // ["0x3333333333333333333333333333333333333333"]

    //     bytes32 root = 0xc6ce8ae383124b268df66d71f0af2206e6dafb13eba0b03806eed8a4e7991329;

    //     // update merkle root
    //     ionPool.updateWhitelistMerkleRoot(root);

    //     // verify
    //     ionPool.onlyWhitelist()

    // }
}
