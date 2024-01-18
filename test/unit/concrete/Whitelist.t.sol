// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Whitelist } from "src/Whitelist.sol";
import { Test } from "forge-std/Test.sol";

contract MockModifiers {
    Whitelist whitelist;

    error NotWhitelistedBorrower(address addr);
    error NotWhitelistedLender(address addr);

    constructor(address _whitelist) {
        whitelist = Whitelist(_whitelist);
    }

    modifier onlyWhitelistedBorrowers(uint8 ilkIndex, bytes32[] memory proof) {
        whitelist.isWhitelistedBorrower(ilkIndex, msg.sender, msg.sender, proof); // error from whitelist
        _;
    }

    modifier onlyWhitelistedLenders(bytes32[] memory proof) {
        whitelist.isWhitelistedLender(msg.sender, msg.sender, proof); // error from whitelist
        _;
    }

    function onlyBorrowersFunction(
        uint8 ilkIndex,
        bytes32[] memory proof
    )
        external
        view
        onlyWhitelistedBorrowers(ilkIndex, proof)
        returns (bool)
    {
        return true;
    }

    function onlyLendersFunction(bytes32[] memory proof) external view onlyWhitelistedLenders(proof) returns (bool) {
        return true;
    }
}

contract WhitelistMockTest is Test {
    Whitelist whitelist;

    function setUp() public {
        bytes32 lendersRoot = 0;

        bytes32[] memory borrowersRoots = new bytes32[](3);
        borrowersRoots[0] = 0;
        borrowersRoots[1] = 0;
        borrowersRoots[2] = 0;

        whitelist = new Whitelist(borrowersRoots, lendersRoot);
    }

    function test_UpdateRoots() public {
        bytes32 borrowersRoot0 = bytes32(uint256(1));
        bytes32 borrowersRoot1 = bytes32(uint256(2));
        bytes32 borrowersRoot2 = bytes32(uint256(3));

        bytes32 lendersRoot = 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11;

        whitelist.updateBorrowersRoot(0, borrowersRoot0);
        whitelist.updateBorrowersRoot(1, borrowersRoot1);
        whitelist.updateBorrowersRoot(2, borrowersRoot2);

        whitelist.updateLendersRoot(lendersRoot);

        assertEq(whitelist.lendersRoot(), lendersRoot, "update lenders root");
        assertEq(whitelist.borrowersRoot(0), borrowersRoot0, "update borrowers root 0");
        assertEq(whitelist.borrowersRoot(1), borrowersRoot1, "update borrowers root 1");
        assertEq(whitelist.borrowersRoot(2), borrowersRoot2, "update borrowers root 2");
    }

    // --- Mock Tests ---

    /**
     * @dev Uninitialized or zero merkle roots should always return true
     */
    function test_MerkleRootUninitializedReturnsTrue() public {
        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        assertTrue(mockModifiers.onlyBorrowersFunction(0, new bytes32[](0)));
        assertTrue(mockModifiers.onlyBorrowersFunction(1, new bytes32[](0)));
        assertTrue(mockModifiers.onlyBorrowersFunction(2, new bytes32[](0)));
        assertTrue(mockModifiers.onlyBorrowersFunction(3, new bytes32[](0)));

        assertTrue(mockModifiers.onlyLendersFunction(new bytes32[](0)));
    }

    function test_WhitelisBorrowerValidProof() public {
        // generate merkle root
        // [["0x1111111111111111111111111111111111111111"],
        // ["0x2222222222222222222222222222222222222222"],
        // ["0x3333333333333333333333333333333333333333"]];
        // => 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11
        uint8 ilkIndex = 0;
        whitelist.updateBorrowersRoot(ilkIndex, 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11);

        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        vm.startPrank(0x1111111111111111111111111111111111111111);
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = bytes32(0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192);
        proof[1] = bytes32(0xcef861ae49469220eac9703d1077fa45b0a3ae990e4a8a7d325472f93cbca30e);
        mockModifiers.onlyBorrowersFunction(ilkIndex, proof);
        vm.stopPrank();
    }

    function test_RevertWhen_WhitelistMockBorrowerInvalidProof() public {
        // generate merkle root
        // [["0x1111111111111111111111111111111111111111"],
        // ["0x2222222222222222222222222222222222222222"],
        // ["0x3333333333333333333333333333333333333333"]];
        // => 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11
        uint8 ilkIndex = 0;
        whitelist.updateBorrowersRoot(ilkIndex, 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11);

        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        // correct address
        address addr = 0x1111111111111111111111111111111111111111;
        vm.startPrank(addr);
        bytes32[] memory proof = new bytes32[](2);
        // but wrong proof
        proof[0] = bytes32(0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192);
        proof[1] = bytes32(0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192);
        vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, ilkIndex, addr));
        mockModifiers.onlyBorrowersFunction(ilkIndex, proof);
        vm.stopPrank();
    }

    function test_RevertWhen_WhitelistMockBorrowerInvalidAddress() public {
        uint8 ilkIndex = 0;
        // generate merkle root
        // [["0x1111111111111111111111111111111111111111"],
        // ["0x2222222222222222222222222222222222222222"],
        // ["0x3333333333333333333333333333333333333333"]];
        // => 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11

        whitelist.updateBorrowersRoot(ilkIndex, 0xcbbe6d63f5be7e5334d28b46ad9cbf99a89625899443061c6fd58fcae90b2d11);
        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        // wrong address
        address addr = 0x4444444444444444444444444444444444444444;
        vm.startPrank(addr);
        bytes32[] memory proof = new bytes32[](2);
        // valid proof for 0x111...
        proof[0] = bytes32(0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192);
        proof[1] = bytes32(0xcef861ae49469220eac9703d1077fa45b0a3ae990e4a8a7d325472f93cbca30e);
        vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, ilkIndex, addr));
        mockModifiers.onlyBorrowersFunction(ilkIndex, proof);
        vm.stopPrank();
    }

    function test_WhitelistLenderValidProof() public {
        // generate merkle root
        // ["0x0000000000000000000000000000000000000001"],
        // ["0x0000000000000000000000000000000000000002"],
        // ["0x0000000000000000000000000000000000000003"],
        // ["0x0000000000000000000000000000000000000004"],
        // ["0x0000000000000000000000000000000000000005"],
        // => 0x21abd2f655ded75d91fbd5e0b1ad35171a675fd315a077efa7f2d555a26e7094

        whitelist.updateLendersRoot(0x21abd2f655ded75d91fbd5e0b1ad35171a675fd315a077efa7f2d555a26e7094);
        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        // correct address
        address addr1 = address(1);
        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = bytes32(0x2584db4a68aa8b172f70bc04e2e74541617c003374de6eb4b295e823e5beab01);
        proof1[1] = bytes32(0xc949c2dc5da2bd9a4f5ae27532dfbb3551487bed50825cd099ff5d0a8d613ab5);
        vm.startPrank(addr1);
        assertTrue(mockModifiers.onlyLendersFunction(proof1));
        vm.stopPrank();

        // correct address
        address addr3 = address(3);
        bytes32[] memory proof3 = new bytes32[](2);
        proof3[0] = bytes32(0xb5d9d894133a730aa651ef62d26b0ffa846233c74177a591a4a896adfda97d22);
        proof3[1] = bytes32(0xc949c2dc5da2bd9a4f5ae27532dfbb3551487bed50825cd099ff5d0a8d613ab5);
        vm.startPrank(addr3);
        assertTrue(mockModifiers.onlyLendersFunction(proof3));
        vm.stopPrank();

        address addr5 = address(5);
        bytes32[] memory proof5 = new bytes32[](3);
        proof5[0] = bytes32(0x1ab0c6948a275349ae45a06aad66a8bd65ac18074615d53676c09b67809099e0);
        proof5[1] = bytes32(0xc167b0e3c82238f4f2d1a50a8b3a44f96311d77b148c30dc0ef863e1a060dcb6);
        proof5[2] = bytes32(0x1a6dbeb0d179031e5261494ac4b6ee4e284665e8d2ea3ff44f7a2ddf5ca07bb7);
        vm.startPrank(addr5);
        assertTrue(mockModifiers.onlyLendersFunction(proof5));
        vm.stopPrank();
    }

    function test_WhitelistLenderInvalidProof() public {
        // generate merkle root
        // ["0x0000000000000000000000000000000000000001"],
        // ["0x0000000000000000000000000000000000000002"],
        // ["0x0000000000000000000000000000000000000003"],
        // ["0x0000000000000000000000000000000000000004"],
        // ["0x0000000000000000000000000000000000000005"],
        // => 0x21abd2f655ded75d91fbd5e0b1ad35171a675fd315a077efa7f2d555a26e7094

        whitelist.updateLendersRoot(0x21abd2f655ded75d91fbd5e0b1ad35171a675fd315a077efa7f2d555a26e7094);
        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        // correct address
        address addr1 = address(1);
        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = bytes32(0x2584db4a68aa8b172f70bc04e2e74541617c003374de6eb4b295e823e5beab01);
        proof1[1] = bytes32(uint256(1)); // invalid proof
        vm.startPrank(addr1);
        vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedLender.selector, addr1));
        mockModifiers.onlyLendersFunction(proof1);
        vm.stopPrank();

        // correct address
        address addr3 = address(3);
        bytes32[] memory proof3 = new bytes32[](2);
        proof3[0] = bytes32(uint256(0));
        proof3[1] = bytes32(0xc949c2dc5da2bd9a4f5ae27532dfbb3551487bed50825cd099ff5d0a8d613ab5);
        vm.startPrank(addr3);
        vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedLender.selector, addr3));
        mockModifiers.onlyLendersFunction(proof3);
        vm.stopPrank();

        address addr5 = address(5);
        bytes32[] memory proof5 = new bytes32[](3);
        proof5[0] = bytes32(0x1ab0c6948a275349ae45a06aad66a8bd65ac18074615d53676c09b67809099e0);
        proof5[1] = bytes32(uint256(4));
        proof5[2] = bytes32(0x1a6dbeb0d179031e5261494ac4b6ee4e284665e8d2ea3ff44f7a2ddf5ca07bb7);
        vm.startPrank(addr5);
        vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedLender.selector, addr5));
        mockModifiers.onlyLendersFunction(proof5);
        vm.stopPrank();
    }

    function test_ApprovedAddressCanBorrowWithoutProof() public {
        uint8 ilkIndex = 0;
        address protocol = address(1);
        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        whitelist.approveProtocolWhitelist(protocol);

        vm.startPrank(protocol);
        assertTrue(mockModifiers.onlyBorrowersFunction(ilkIndex, new bytes32[](0)));
        vm.stopPrank();
    }

    function test_ApprovedAddressCanLendWithoutProof() public {
        address protocol = address(1);
        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        whitelist.approveProtocolWhitelist(protocol);

        vm.startPrank(protocol);
        assertTrue(mockModifiers.onlyLendersFunction(new bytes32[](0)));
        vm.stopPrank();
    }

    function test_RevertWhen_RevokedAddressBorrowsWithoutProof() public {
        uint8 ilkIndex = 0;

        // borrow whitelist is not empty
        whitelist.updateBorrowersRoot(ilkIndex, bytes32(uint256(1)));

        address protocol = address(1);
        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        whitelist.approveProtocolWhitelist(protocol);

        vm.startPrank(protocol);
        assertTrue(mockModifiers.onlyBorrowersFunction(ilkIndex, new bytes32[](0)));
        vm.stopPrank();

        whitelist.revokeProtocolWhitelist(protocol);

        vm.startPrank(protocol);
        vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, ilkIndex, protocol));
        mockModifiers.onlyBorrowersFunction(ilkIndex, new bytes32[](0));
        vm.stopPrank();
    }

    function test_RevertWhen_RevokedAddressLendsWithoutProof() public {
        // lender whitelist is not empty
        whitelist.updateLendersRoot(bytes32(uint256(1)));

        address protocol = address(1);
        MockModifiers mockModifiers = new MockModifiers(address(whitelist));

        whitelist.approveProtocolWhitelist(protocol);

        vm.startPrank(protocol);
        assertTrue(mockModifiers.onlyLendersFunction(new bytes32[](0)));
        vm.stopPrank();

        whitelist.revokeProtocolWhitelist(protocol);

        vm.startPrank(protocol);
        vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedLender.selector, protocol));
        mockModifiers.onlyLendersFunction(new bytes32[](0));
        vm.stopPrank();
    }

    function test_Ownable2Step() public {
        address newOwner = address(1);

        bytes32[] memory borrowersRoots = new bytes32[](3);
        borrowersRoots[0] = 0;
        borrowersRoots[1] = 0;
        borrowersRoots[2] = 0;

        whitelist = new Whitelist(borrowersRoots, 0);

        assertEq(whitelist.owner(), address(this));

        whitelist.transferOwnership(newOwner);

        assertEq(whitelist.owner(), address(this));
        assertEq(whitelist.pendingOwner(), newOwner);

        vm.startPrank(newOwner);
        whitelist.acceptOwnership();
        vm.stopPrank();

        assertEq(whitelist.owner(), newOwner);
    }

    function test_RevertWhen_UnauthorizedAddressAcceptsOwnership() public { }
}

contract WhitelistIntegrationTest is Test {
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
