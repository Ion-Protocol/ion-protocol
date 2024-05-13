// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20PresetMinterPauser } from "./../../../helpers/ERC20PresetMinterPauser.sol";
import { VaultSharedSetup } from "./../../../helpers/VaultSharedSetup.sol";

import { WadRayMath, RAY } from "./../../../../src/libraries/math/WadRayMath.sol";
import { Vault } from "./../../../../src/vault/Vault.sol";
import { IonPool } from "./../../../../src/IonPool.sol";
import { IIonPool } from "./../../../../src/interfaces/IIonPool.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import { IAccessControl } from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

using EnumerableSet for EnumerableSet.AddressSet;
using WadRayMath for uint256;
using Math for uint256;

contract VaultSetUpTest is VaultSharedSetup {
    function setUp() public override {
        super.setUp();
    }

    function test_AddSupportedMarketsSeparately() public {
        vault = new Vault(
            BASE_ASSET, FEE_RECIPIENT, ZERO_FEES, "Ion Vault Token", "IVT", INITIAL_DELAY, VAULT_ADMIN, emptyMarketsArgs
        );

        vm.startPrank(vault.defaultAdmin());
        vault.grantRole(vault.OWNER_ROLE(), OWNER);
        vault.grantRole(vault.ALLOCATOR_ROLE(), OWNER);
        vm.stopPrank();

        vm.startPrank(OWNER);

        IIonPool[] memory market1 = new IIonPool[](1);
        market1[0] = weEthIonPool;
        IIonPool[] memory market2 = new IIonPool[](1);
        market2[0] = rsEthIonPool;
        IIonPool[] memory market3 = new IIonPool[](1);
        market3[0] = rswEthIonPool;

        uint256[] memory allocationCaps = new uint256[](1);
        uint256 allocationCap = 1 ether;
        allocationCaps[0] = allocationCap;

        vault.addSupportedMarkets(market1, allocationCaps, market1, market1);

        address[] memory supportedMarkets1 = vault.getSupportedMarkets();

        assertEq(supportedMarkets1.length, 1, "supported markets length one");
        assertEq(supportedMarkets1[0], address(weEthIonPool), "first supported markets address");

        assertEq(address(vault.supplyQueue(0)), address(weEthIonPool), "first in supply queue");
        assertEq(address(vault.withdrawQueue(0)), address(weEthIonPool), "first in withdraw queue");
        assertEq(vault.caps(weEthIonPool), allocationCap, "weEthIonPool allocation cap");

        IIonPool[] memory queue2 = new IIonPool[](2);
        queue2[0] = weEthIonPool;
        queue2[1] = rsEthIonPool;

        vault.addSupportedMarkets(market2, allocationCaps, queue2, queue2);
        address[] memory supportedMarkets2 = vault.getSupportedMarkets();
        assertEq(supportedMarkets2.length, 2, "supported markets length two");
        assertEq(supportedMarkets2[1], address(rsEthIonPool), "second supported markets address");

        assertEq(address(vault.supplyQueue(1)), address(rsEthIonPool), "second in supply queue");
        assertEq(address(vault.withdrawQueue(1)), address(rsEthIonPool), "second in withdraw queue");
        assertEq(vault.caps(rsEthIonPool), allocationCap, "rsEthIonPool allocation cap");

        IIonPool[] memory queue3 = new IIonPool[](3);
        queue3[0] = weEthIonPool;
        queue3[1] = rsEthIonPool;
        queue3[2] = rswEthIonPool;

        vault.addSupportedMarkets(market3, allocationCaps, queue3, queue3);
        address[] memory supportedMarkets3 = vault.getSupportedMarkets();
        assertEq(supportedMarkets3.length, 3, "supported markets length three");
        assertEq(supportedMarkets3[2], address(rswEthIonPool), "third supported markets address");

        assertEq(address(vault.supplyQueue(2)), address(rswEthIonPool), "third in supply queue");
        assertEq(address(vault.withdrawQueue(2)), address(rswEthIonPool), "third in withdraw queue");
        assertEq(vault.caps(rswEthIonPool), allocationCap, "rswEthIonPool allocation cap");

        vm.stopPrank();
    }

    function test_AddSupportedMarketsTogether() public {
        vault = new Vault(
            BASE_ASSET, FEE_RECIPIENT, ZERO_FEES, "Ion Vault Token", "IVT", INITIAL_DELAY, VAULT_ADMIN, emptyMarketsArgs
        );

        vm.startPrank(vault.defaultAdmin());
        vault.grantRole(vault.OWNER_ROLE(), OWNER);
        vault.grantRole(vault.ALLOCATOR_ROLE(), OWNER);
        vm.stopPrank();

        vm.startPrank(OWNER);

        IIonPool[] memory markets = new IIonPool[](3);
        markets[0] = weEthIonPool;
        markets[1] = rsEthIonPool;
        markets[2] = rswEthIonPool;

        uint256[] memory allocationCaps = new uint256[](3);
        allocationCaps[0] = 1 ether;
        allocationCaps[1] = 2 ether;
        allocationCaps[2] = 3 ether;

        vault.addSupportedMarkets(markets, allocationCaps, markets, markets);
        address[] memory supportedMarkets = vault.getSupportedMarkets();

        assertEq(supportedMarkets.length, 3, "supported markets length");
        assertEq(supportedMarkets[0], address(weEthIonPool), "first supported markets address");
        assertEq(supportedMarkets[1], address(rsEthIonPool), "second supported markets address");
        assertEq(supportedMarkets[2], address(rswEthIonPool), "third supported markets address");

        assertEq(address(vault.supplyQueue(0)), address(weEthIonPool), "first in supply queue");
        assertEq(address(vault.supplyQueue(1)), address(rsEthIonPool), "second in supply queue");
        assertEq(address(vault.supplyQueue(2)), address(rswEthIonPool), "third in supply queue");

        assertEq(address(vault.withdrawQueue(0)), address(weEthIonPool), "first in withdraw queue");
        assertEq(address(vault.withdrawQueue(1)), address(rsEthIonPool), "second in withdraw queue");
        assertEq(address(vault.withdrawQueue(2)), address(rswEthIonPool), "third in withdraw queue");

        assertEq(vault.caps(weEthIonPool), 1 ether, "weEthIonPool allocation cap");
        assertEq(vault.caps(rsEthIonPool), 2 ether, "rsEthIonPool allocation cap");
        assertEq(vault.caps(rswEthIonPool), 3 ether, "rswEthIonPool allocation cap");

        vm.stopPrank();
    }

    function test_Revert_AddSupportedMarkets_InvalidSupportedMarkets() public {
        IERC20 wrongBaseAsset = IERC20(address(new ERC20PresetMinterPauser("Wrong Wrapped Staked ETH", "wstETH")));

        IIonPool newIonPool = deployIonPool(wrongBaseAsset, WEETH, address(this));

        IIonPool[] memory markets = new IIonPool[](1);
        markets[0] = newIonPool;

        uint256[] memory allocationCaps = new uint256[](1);
        allocationCaps[0] = 1e18;

        IIonPool[] memory queue = new IIonPool[](4);
        queue[0] = weEthIonPool;
        queue[1] = rsEthIonPool;
        queue[2] = rswEthIonPool;
        queue[3] = newIonPool;

        vm.startPrank(OWNER);

        // wrong base asset revert
        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidUnderlyingAsset.selector, newIonPool));
        vault.addSupportedMarkets(markets, allocationCaps, queue, queue);

        // zero address revert
        vm.expectRevert();
        markets[0] = IIonPool(address(0));
        vault.addSupportedMarkets(markets, allocationCaps, queue, queue);

        vm.stopPrank();
    }

    function test_Revert_AddSupportedMarkets_MarketAlreadySupported() public { }

    function test_RemoveSingleSupportedMarket() public {
        uint256[] memory allocationCaps = new uint256[](1);
        allocationCaps[0] = 1e18;

        IIonPool[] memory marketsToRemove = new IIonPool[](1);
        marketsToRemove[0] = weEthIonPool;

        IIonPool[] memory supplyQueue = new IIonPool[](2);
        supplyQueue[0] = rsEthIonPool;
        supplyQueue[1] = rswEthIonPool;

        IIonPool[] memory withdrawQueue = new IIonPool[](2);
        withdrawQueue[0] = rswEthIonPool;
        withdrawQueue[1] = rsEthIonPool;

        vm.prank(OWNER);
        vault.updateAllocationCaps(marketsToRemove, allocationCaps);

        assertEq(vault.caps(weEthIonPool), 1e18, "allocation cap");
        assertEq(BASE_ASSET.allowance(address(vault), address(weEthIonPool)), type(uint256).max, "allowance");

        vm.prank(OWNER);
        vault.removeSupportedMarkets(marketsToRemove, supplyQueue, withdrawQueue);

        address[] memory supportedMarkets = vault.getSupportedMarkets();

        assertEq(supportedMarkets.length, 2, "supported markets");
        // weEth rsEth rswEth => rswEth rsEth
        // weEth is swapped and popped
        assertEq(address(supportedMarkets[0]), address(rswEthIonPool), "first in supported markets");
        assertEq(address(supportedMarkets[1]), address(rsEthIonPool), "second in supported markets");

        assertEq(address(vault.supplyQueue(0)), address(rsEthIonPool), "first in supply queue");
        assertEq(address(vault.supplyQueue(1)), address(rswEthIonPool), "second in supply queue");

        assertEq(address(vault.withdrawQueue(0)), address(rswEthIonPool), "first in withdraw queue");
        assertEq(address(vault.withdrawQueue(1)), address(rsEthIonPool), "second in withdraw queue");

        assertEq(vault.caps(weEthIonPool), 0, "allocation cap deleted");
        assertEq(BASE_ASSET.allowance(address(vault), address(weEthIonPool)), 0, "approval revoked");
    }

    function test_RemoveAllSupportedMarkets() public {
        uint256[] memory allocationCaps = new uint256[](3);
        allocationCaps[0] = 1e18;
        allocationCaps[1] = 1e18;
        allocationCaps[2] = 1e18;

        IIonPool[] memory marketsToRemove = new IIonPool[](3);
        marketsToRemove[0] = weEthIonPool;
        marketsToRemove[1] = rsEthIonPool;
        marketsToRemove[2] = rswEthIonPool;

        IIonPool[] memory supplyQueue = new IIonPool[](0);

        IIonPool[] memory withdrawQueue = new IIonPool[](0);

        vm.prank(OWNER);
        vault.updateAllocationCaps(marketsToRemove, allocationCaps);

        vm.prank(OWNER);
        vault.removeSupportedMarkets(marketsToRemove, supplyQueue, withdrawQueue);

        address[] memory supportedMarkets = vault.getSupportedMarkets();

        assertEq(supportedMarkets.length, 0, "supported markets");

        vm.expectRevert();
        vault.supplyQueue(0);
        vm.expectRevert();
        vault.withdrawQueue(0);

        assertEq(vault.caps(weEthIonPool), 0, "allocation cap deleted");
        assertEq(vault.caps(rsEthIonPool), 0, "allocation cap deleted");
        assertEq(vault.caps(rswEthIonPool), 0, "allocation cap deleted");

        assertEq(BASE_ASSET.allowance(address(vault), address(weEthIonPool)), 0, "approval revoked");
        assertEq(BASE_ASSET.allowance(address(vault), address(rsEthIonPool)), 0, "approval revoked");
        assertEq(BASE_ASSET.allowance(address(vault), address(rswEthIonPool)), 0, "approval revoked");
    }

    function test_Revert_RemoveMarkets_IdleMarketWithBalance() public {
        IIonPool IDLE = vault.IDLE();

        IIonPool[] memory market = new IIonPool[](1);
        market[0] = IDLE;

        uint256[] memory allocationCaps = new uint256[](1);
        allocationCaps[0] = 10e18;

        IIonPool[] memory queue = new IIonPool[](4);
        queue[0] = IDLE;
        queue[1] = weEthIonPool;
        queue[2] = rsEthIonPool;
        queue[3] = rswEthIonPool;

        vm.prank(OWNER);
        vault.addSupportedMarkets(market, allocationCaps, queue, queue);

        // make a deposit into the idle pool
        uint256 depositAmount = 5e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        vault.deposit(depositAmount, address(this));

        assertEq(BASE_ASSET.balanceOf(address(vault)), depositAmount, "deposited to IDLE");

        IIonPool[] memory newQueue = new IIonPool[](3);
        queue[0] = weEthIonPool;
        queue[1] = rsEthIonPool;
        queue[2] = rswEthIonPool;

        vm.prank(OWNER);
        vm.expectRevert(Vault.InvalidIdleMarketRemovalNonZeroBalance.selector);
        vault.removeSupportedMarkets(market, newQueue, newQueue);
    }

    function test_Revert_RemoveMarkets_IonPoolMarketWithBalance() public {
        IIonPool[] memory market = new IIonPool[](1);
        market[0] = weEthIonPool;

        uint256[] memory allocationCaps = new uint256[](1);
        allocationCaps[0] = 10e18;

        IIonPool[] memory queue = new IIonPool[](2);
        queue[0] = rsEthIonPool;
        queue[1] = rswEthIonPool;

        vm.prank(OWNER);
        vault.updateAllocationCaps(market, allocationCaps);

        uint256 depositAmount = 5e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        vault.deposit(depositAmount, address(this));

        assertGt(weEthIonPool.normalizedBalanceOf(address(vault)), 0, "deposited to weEthIonPool");

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidMarketRemovalNonZeroSupply.selector, weEthIonPool));
        vault.removeSupportedMarkets(market, queue, queue);
    }

    function test_Revert_RemoveMarkets_MarketNotSupported() public {
        IIonPool[] memory market = new IIonPool[](1);
        market[0] = IDLE;

        IIonPool[] memory queue = new IIonPool[](3);
        queue[0] = weEthIonPool;
        queue[1] = rsEthIonPool;
        queue[2] = rswEthIonPool;

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Vault.MarketNotSupported.selector, IDLE));
        vault.removeSupportedMarkets(market, queue, queue);
    }

    function test_Revert_RemoveMarkets_WrongQueues() public {
        // wrong queue length
        IIonPool[] memory market = new IIonPool[](1);
        market[0] = weEthIonPool;

        // there should be 2 markets left, but this inputs 3 markets into the queues
        IIonPool[] memory queue = new IIonPool[](3);
        queue[0] = weEthIonPool;
        queue[1] = rsEthIonPool;
        queue[2] = rswEthIonPool;

        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidQueueLength.selector, 3, 2));
        vault.removeSupportedMarkets(market, queue, queue);
    }

    function test_RemoveMarkets_WithMulticall() public {
        // for removing weEthIonPool
        IIonPool[] memory marketsToRemove = new IIonPool[](1);
        marketsToRemove[0] = weEthIonPool;

        IIonPool[] memory queue = new IIonPool[](2);
        queue[0] = rsEthIonPool;
        queue[1] = rswEthIonPool;

        // for updating allocation caps

        uint256[] memory allocationCaps = new uint256[](3);
        allocationCaps[0] = 10e18;
        allocationCaps[1] = 10e18;
        allocationCaps[2] = 10e18;

        // for fully withdrawing from weEthIonPool and fully depositing to rsEthIonPool
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](2);
        allocs[0] = Vault.MarketAllocation({ pool: weEthIonPool, assets: type(int256).min });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: type(int256).max });

        vm.prank(OWNER);
        vault.updateAllocationCaps(markets, allocationCaps);

        uint256 depositAmount = 5e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);
        vault.deposit(depositAmount, address(this));

        assertGt(weEthIonPool.normalizedBalanceOf(address(vault)), 0, "deposited to weEthIonPool");

        bytes memory reallocateCalldata = abi.encodeWithSelector(Vault.reallocate.selector, allocs);

        bytes memory removeMarketCalldata =
            abi.encodeWithSelector(Vault.removeSupportedMarkets.selector, marketsToRemove, queue, queue);

        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = reallocateCalldata;
        multicallData[1] = removeMarketCalldata;

        vm.prank(OWNER);
        vault.multicall(multicallData);

        vm.expectRevert(abi.encodeWithSelector(Vault.MarketNotSupported.selector, weEthIonPool));
        vault.supportedMarketsIndexOf(address(weEthIonPool));

        assertEq(vault.supportedMarketsLength(), 2, "supported markets length");
        assertTrue(!vault.containsSupportedMarket(address(weEthIonPool)), "does not contain weEthIonPool");
    }

    function test_UpdateSupplyQueue() public {
        IIonPool[] memory supplyQueue = new IIonPool[](3);
        supplyQueue[0] = rsEthIonPool;
        supplyQueue[1] = rswEthIonPool;
        supplyQueue[2] = weEthIonPool;

        vm.startPrank(OWNER);
        vault.updateSupplyQueue(supplyQueue);

        assertEq(address(vault.supplyQueue(0)), address(supplyQueue[0]), "updated supply queue");
        assertEq(address(vault.supplyQueue(1)), address(supplyQueue[1]), "updated supply queue");
        assertEq(address(vault.supplyQueue(2)), address(supplyQueue[2]), "updated supply queue");
    }

    function test_Revert_UpdateSupplyQueue() public {
        IIonPool[] memory invalidLengthQueue = new IIonPool[](5);
        for (uint8 i = 0; i < 5; i++) {
            invalidLengthQueue[i] = weEthIonPool;
        }

        vm.startPrank(OWNER);

        vm.expectRevert(abi.encodeWithSelector(Vault.InvalidQueueLength.selector, 5, 3));
        vault.updateSupplyQueue(invalidLengthQueue);

        IIonPool[] memory zeroAddressQueue = new IIonPool[](3);

        vm.expectRevert(abi.encodeWithSelector(Vault.MarketNotSupported.selector, address(0)));
        vault.updateSupplyQueue(zeroAddressQueue);

        IIonPool wrongIonPool = IIonPool(address(uint160(uint256(keccak256("address not in supported markets")))));
        IIonPool[] memory notSupportedQueue = new IIonPool[](3);
        notSupportedQueue[0] = rsEthIonPool;
        notSupportedQueue[1] = rswEthIonPool;
        notSupportedQueue[2] = wrongIonPool;

        vm.expectRevert(abi.encodeWithSelector(Vault.MarketNotSupported.selector, wrongIonPool));
        vault.updateSupplyQueue(notSupportedQueue);
    }

    function test_UpdateWithdrawQueue() public { }

    function test_Revert_UpdateWithdrawQueue() public { }

    function test_Revert_DuplicateIonPoolArray() public { }

    function test_UpdateFeePercentage() public {
        vm.prank(OWNER);
        vault.updateFeePercentage(0.1e27);

        assertEq(0.1e27, vault.feePercentage(), "fee percentage");
    }

    function test_UpdateFeeRecipient() public {
        address newFeeRecipient = newAddress("new fee recipient");

        vm.prank(OWNER);
        vault.updateFeeRecipient(newFeeRecipient);

        assertEq(newFeeRecipient, vault.feeRecipient(), "fee recipient");
    }
}

contract VaultRolesAndPrivilegedFunctions is VaultSharedSetup {
    IIonPool newIonPool;
    IIonPool[] newSupplyQueue;
    IIonPool[] newWithdrawQueue;

    function setUp() public override {
        super.setUp();

        newIonPool = deployIonPool(BASE_ASSET, WEETH, address(this));

        newSupplyQueue = new IIonPool[](4);
        newSupplyQueue[0] = newIonPool;
        newSupplyQueue[1] = weEthIonPool;
        newSupplyQueue[2] = rsEthIonPool;
        newSupplyQueue[3] = rswEthIonPool;

        newWithdrawQueue = new IIonPool[](4);
        newWithdrawQueue[0] = newIonPool;
        newWithdrawQueue[1] = rsEthIonPool;
        newWithdrawQueue[2] = rswEthIonPool;
        newWithdrawQueue[3] = weEthIonPool;
    }

    function test_DefaultAdmin_RoleAssignment() public {
        address owner1 = newAddress("owner1");
        address owner2 = newAddress("owner2");

        address allocator1 = newAddress("allocator1");

        assertEq(vault.DEFAULT_ADMIN_ROLE(), vault.getRoleAdmin(vault.OWNER_ROLE()), "owner role admin");
        assertEq(vault.DEFAULT_ADMIN_ROLE(), vault.getRoleAdmin(vault.ALLOCATOR_ROLE()), "allocator role admin");

        vm.startPrank(vault.defaultAdmin());
        vault.grantRole(vault.OWNER_ROLE(), owner1);
        vault.grantRole(vault.OWNER_ROLE(), owner2);
        vault.grantRole(vault.ALLOCATOR_ROLE(), allocator1);
        vm.stopPrank();

        assertTrue(vault.hasRole(vault.OWNER_ROLE(), owner1), "owner1");
        assertTrue(vault.hasRole(vault.OWNER_ROLE(), owner2), "owner2");
        assertTrue(vault.hasRole(vault.ALLOCATOR_ROLE(), allocator1), "allocator1");

        vm.startPrank(vault.defaultAdmin());
        vault.revokeRole(vault.OWNER_ROLE(), owner1);
        vm.stopPrank();

        assertFalse(vault.hasRole(vault.OWNER_ROLE(), owner1), "owner1 revoked");
    }

    function test_OwnerRole() public {
        address notOwner = newAddress("not owner");
        address owner = newAddress("owner");

        uint256 newFeePerc = 0.05e27;
        address newFeeRecipient = newAddress("new fee recipient");

        IIonPool[] memory marketsToAdd = new IIonPool[](1);
        marketsToAdd[0] = newIonPool;

        uint256[] memory allocationCaps = new uint256[](1);
        allocationCaps[0] = 1e18;

        IIonPool[] memory ionPoolToUpdate = new IIonPool[](1);
        ionPoolToUpdate[0] = weEthIonPool;

        vm.startPrank(vault.defaultAdmin());
        vault.grantRole(vault.OWNER_ROLE(), owner);
        vm.stopPrank();

        // from owner
        vm.startPrank(owner);
        vault.updateFeePercentage(newFeePerc);
        vault.updateFeeRecipient(newFeeRecipient);
        vault.updateAllocationCaps(ionPoolToUpdate, allocationCaps);
        vm.stopPrank();

        // grant owner also the allocator role
        vm.startPrank(vault.defaultAdmin());
        vault.grantRole(vault.ALLOCATOR_ROLE(), owner);
        vm.stopPrank();

        // from owner with also the allocator role
        vm.startPrank(owner);
        vault.addSupportedMarkets(marketsToAdd, allocationCaps, newSupplyQueue, newWithdrawQueue);
        vm.stopPrank();

        // not from owner
        vm.startPrank(notOwner);

        bytes memory notOwnerRevert = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, notOwner, vault.OWNER_ROLE()
        );

        vm.expectRevert(notOwnerRevert);
        vault.updateFeePercentage(newFeePerc);

        vm.expectRevert(notOwnerRevert);
        vault.updateFeeRecipient(newFeeRecipient);

        vm.expectRevert(notOwnerRevert);
        vault.addSupportedMarkets(marketsToAdd, allocationCaps, newSupplyQueue, newWithdrawQueue);

        vm.expectRevert(notOwnerRevert);
        vault.updateAllocationCaps(ionPoolToUpdate, allocationCaps);

        vm.stopPrank();
    }

    function test_AllocatorRole() public {
        address notAllocator = newAddress("not allocator");
        address allocator = newAddress("allocator");

        newSupplyQueue = new IIonPool[](3);
        newSupplyQueue[0] = rswEthIonPool;
        newSupplyQueue[1] = weEthIonPool;
        newSupplyQueue[2] = rsEthIonPool;

        newWithdrawQueue = new IIonPool[](3);
        newWithdrawQueue[0] = weEthIonPool;
        newWithdrawQueue[1] = rsEthIonPool;
        newWithdrawQueue[2] = rswEthIonPool;

        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: 0 });
        allocs[1] = Vault.MarketAllocation({ pool: weEthIonPool, assets: 0 });
        allocs[2] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: 0 });

        bytes memory notAllocatorRevert = abi.encodeWithSelector(
            IAccessControl.AccessControlUnauthorizedAccount.selector, notAllocator, vault.ALLOCATOR_ROLE()
        );

        vm.startPrank(vault.defaultAdmin());
        vault.grantRole(vault.ALLOCATOR_ROLE(), allocator);
        vm.stopPrank();

        vm.startPrank(notAllocator);

        vm.expectRevert(notAllocatorRevert);
        vault.updateSupplyQueue(newSupplyQueue);

        vm.expectRevert(notAllocatorRevert);
        vault.updateWithdrawQueue(newWithdrawQueue);

        vm.expectRevert(notAllocatorRevert);
        vault.reallocate(allocs);

        vm.stopPrank();

        vm.startPrank(allocator);
        vault.updateSupplyQueue(newSupplyQueue);
        vault.updateWithdrawQueue(newWithdrawQueue);
        vault.reallocate(allocs);
        vm.stopPrank();
    }
}

abstract contract VaultDeposit is VaultSharedSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_Deposit_WithoutSupplyCap_WithoutAllocationCap() public {
        uint256 depositAmount = 1e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rsEthIonPool, rswEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        uint256 prevWeEthShares = weEthIonPool.normalizedBalanceOf(address(vault));

        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");
        assertEq(
            weEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevWeEthShares, depositAmount, weEthIonPool.supplyFactor()),
            "vault iToken claim"
        );
    }

    function test_Deposit_WithoutSupplyCap_WithAllocationCap_EqualDeposits() public {
        uint256 depositAmount = 3e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rsEthIonPool, rswEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 1e18, 1e18, 1e18);

        uint256 prevWeEthShares = weEthIonPool.normalizedBalanceOf(address(vault));
        uint256 prevRsEthShares = rsEthIonPool.normalizedBalanceOf(address(vault));
        uint256 prevRswEthShares = rswEthIonPool.normalizedBalanceOf(address(vault));

        // 3e18 gets spread out equally amongst the three pools
        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        assertEq(
            weEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevWeEthShares, 1e18, weEthIonPool.supplyFactor()),
            "weEth vault iToken claim"
        );
        assertEq(
            rsEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevRsEthShares, 1e18, rsEthIonPool.supplyFactor()),
            "rsEth vault iToken claim"
        );
        assertEq(
            rswEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevRswEthShares, 1e18, rswEthIonPool.supplyFactor()),
            "rswEth vault iToken claim"
        );
    }

    function test_Deposit_WithoutSupplyCap_WithAllocationCap_DifferentDeposits() public {
        uint256 depositAmount = 10e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 3e18, 5e18, 7e18);

        uint256 prevWeEthShares = weEthIonPool.normalizedBalanceOf(address(vault));
        uint256 prevRsEthShares = rsEthIonPool.normalizedBalanceOf(address(vault));
        uint256 prevRswEthShares = rswEthIonPool.normalizedBalanceOf(address(vault));

        // 3e18 gets spread out equally amongst the three pools
        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        assertEq(
            weEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevWeEthShares, 2e18, weEthIonPool.supplyFactor()),
            "weEth vault iToken claim"
        );
        assertEq(
            rsEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevRsEthShares, 3e18, rsEthIonPool.supplyFactor()),
            "rsEth vault iToken claim"
        );
        assertEq(
            rswEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevRswEthShares, 5e18, rswEthIonPool.supplyFactor()),
            "rswEth vault iToken claim"
        );
    }

    function test_Deposit_SupplyCap_Below_AllocationCap_DifferentDeposits() public {
        uint256 depositAmount = 12e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        address[] memory supportedMarkets = vault.getSupportedMarkets();

        updateSupplyQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);
        updateSupplyCaps(vault, 3e18, 10e18, 5e18);
        updateAllocationCaps(vault, 5e18, 7e18, 20e18);

        uint256 prevWeEthShares = weEthIonPool.normalizedBalanceOf(address(vault));
        uint256 prevRsEthShares = rsEthIonPool.normalizedBalanceOf(address(vault));
        uint256 prevRswEthShares = rswEthIonPool.normalizedBalanceOf(address(vault));

        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        assertEq(
            weEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevWeEthShares, 2e18, weEthIonPool.supplyFactor()),
            "weEth vault iToken claim"
        );
        assertEq(
            rsEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevRsEthShares, 3e18, rsEthIonPool.supplyFactor()),
            "rsEth vault iToken claim"
        );
        assertEq(
            rswEthIonPool.balanceOf(address(vault)),
            claimAfterDeposit(prevRswEthShares, 7e18, rswEthIonPool.supplyFactor()),
            "rswEth vault iToken claim"
        );
    }

    function test_Revert_Deposit_AllCaps_Filled() public {
        uint256 depositAmount = 12e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);
        updateSupplyCaps(vault, 1e18, 1e18, 1e18);
        updateAllocationCaps(vault, 1e18, 1e18, 1e18);

        vm.expectRevert(Vault.AllSupplyCapsReached.selector);
        vault.deposit(depositAmount, address(this));
    }

    function test_SupplyToIonPool_AllocationCapAndSupplyCapDiffs() public { }

    /**
     * - Exact shares to mint must be minted to the user.
     * - Resulting state should be the same as having used `deposit` after
     * converting the shares to assets.
     */
    function test_Mint_WithoutSupplyCap_WithoutAllocationCap() public {
        uint256 sharesToMint = 1e18;

        setERC20Balance(address(BASE_ASSET), address(this), 100e18);

        uint256 initialAssetBalance = BASE_ASSET.balanceOf(address(this));
        uint256 initialTotalSupply = vault.totalSupply();
        uint256 initialTotalAssets = vault.totalAssets();

        updateSupplyQueue(vault, weEthIonPool, rsEthIonPool, rswEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        uint256 expectedDepositAmount = vault.previewMint(sharesToMint);

        uint256 assetsDeposited = vault.mint(sharesToMint, address(this));

        uint256 assetBalanceDiff = initialAssetBalance - BASE_ASSET.balanceOf(address(this));
        uint256 totalSupplyDiff = vault.totalSupply() - initialTotalSupply;
        uint256 totalAssetsDiff = vault.totalAssets() - initialTotalAssets;

        uint256 totalAssetsRoundingError = (weEthIonPool.supplyFactor() + 2) / RAY + 1;

        assertEq(totalSupplyDiff, sharesToMint, "vault shares total supply");

        // when you deposit, as IonPool rounds in protocol favor, totalAssets() may be lower than expected
        assertLe(
            expectedDepositAmount - totalAssetsDiff, totalAssetsRoundingError, "vault total assetes with rounding error"
        );

        assertEq(vault.balanceOf(address(this)), sharesToMint, "user vault shares balance");
        assertEq(assetBalanceDiff, expectedDepositAmount, "preview amount deposited");
        assertEq(assetsDeposited, expectedDepositAmount, "mint return value");
    }

    function test_Mint_AllMarkets() public { }
}

abstract contract VaultWithdraw is VaultSharedSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_Withdraw_SingleMarket() public {
        uint256 depositAmount = 10e18;
        uint256 withdrawAmount = 5e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        updateWithdrawQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);

        vault.deposit(depositAmount, address(this));

        // state before withdraw
        uint256 prevTotalAssets = vault.totalAssets();
        uint256 prevTotalSupply = vault.totalSupply();
        uint256 prevMaxWithdraw = vault.maxWithdraw(address(this));

        vault.withdraw(withdrawAmount, address(this), address(this));

        // expectation ignoring rounding errors
        uint256 expectedNewTotalAssets = prevTotalAssets - withdrawAmount;
        uint256 expectedMaxWithdraw = prevMaxWithdraw - withdrawAmount;

        uint256 expectedSharesBurned =
            withdrawAmount.mulDiv(prevTotalSupply + 1, prevTotalAssets + 1, Math.Rounding.Ceil);
        uint256 expectedNewTotalSupply = prevTotalSupply - expectedSharesBurned;

        // vault
        assertLe(vault.totalAssets(), expectedNewTotalAssets, "vault total assets");
        assertLe(
            expectedNewTotalAssets - vault.totalAssets(),
            rsEthIonPool.supplyFactor() / RAY,
            "vault total assets rounding error"
        );
        assertEq(vault.totalSupply(), expectedNewTotalSupply, "vault shares total supply");

        assertEq(vault.totalAssets(), rsEthIonPool.balanceOf(address(vault)), "single market for total assets");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "valt's base asset balance should be zero");

        // user
        assertLe(vault.maxWithdraw(address(this)), expectedMaxWithdraw, "user max withdraw");
        assertLe(
            expectedMaxWithdraw - vault.maxWithdraw(address(this)),
            rsEthIonPool.supplyFactor() / RAY,
            "user max withdraw rounding error"
        );

        assertEq(BASE_ASSET.balanceOf(address(this)), withdrawAmount, "user base asset balance");
    }

    function test_Withdraw_MultipleMarkets() public {
        uint256 depositAmount = 10e18;
        uint256 withdrawAmount = 9e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);
        updateSupplyCaps(vault, 2e18, 3e18, 5e18);
        updateAllocationCaps(vault, 2e18, 3e18, 5e18);

        updateWithdrawQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);

        vault.deposit(depositAmount, address(this));

        // state before withdraw
        uint256 prevTotalAssets = vault.totalAssets();
        uint256 prevTotalSupply = vault.totalSupply();
        uint256 prevMaxWithdraw = vault.maxWithdraw(address(this));

        vault.withdraw(withdrawAmount, address(this), address(this));

        uint256 expectedNewTotalAssets = prevTotalAssets - withdrawAmount;
        uint256 expectedMaxWithdraw = prevMaxWithdraw - withdrawAmount;

        uint256 expectedSharesBurned =
            withdrawAmount.mulDiv(prevTotalSupply + 1, prevTotalAssets + 1, Math.Rounding.Ceil);
        uint256 expectedNewTotalSupply = prevTotalSupply - expectedSharesBurned;

        // error bound for resulting total assets after a withdraw
        uint256 totalAssetsRoundingError = totalAssetsREAfterWithdraw(4e18, weEthIonPool.supplyFactor());
        uint256 maxWithdrawRoundingError = maxWithdrawREAfterWithdraw(withdrawAmount, prevTotalAssets, prevTotalSupply);

        // pool1 deposit 2 withdraw 2
        // pool2 deposit 3 withdraw 3
        // pool3 deposit 5 withdraw 4

        // vault
        assertLe(vault.totalAssets(), expectedNewTotalAssets, "vault total assets");
        assertLe(
            expectedNewTotalAssets - vault.totalAssets(),
            weEthIonPool.supplyFactor() / RAY,
            "vault total assets rounding error"
        );
        assertEq(vault.totalSupply(), expectedNewTotalSupply, "vault shares total supply");

        assertEq(rsEthIonPool.balanceOf(address(vault)), 0, "vault pool1 balance");
        assertEq(rswEthIonPool.balanceOf(address(vault)), 0, "vault pool2 balance");
        assertLe(
            expectedNewTotalAssets - weEthIonPool.balanceOf(address(vault)),
            weEthIonPool.supplyFactor() / RAY,
            "vault pool3 balance"
        );

        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "vault base asset balance should be zero");

        // users
        assertLe(
            expectedMaxWithdraw - vault.maxWithdraw(address(this)),
            weEthIonPool.supplyFactor() / RAY,
            "user max withdraw"
        );
    }

    function test_Revert_Withdraw_NotEnoughLiquidity() public {
        uint256 depositAmount = 10e18;
        uint256 withdrawAmount = 20e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateAllocationCaps(vault, 2e18, 3e18, 5e18);

        vault.deposit(depositAmount, address(this));

        vm.expectRevert(Vault.NotEnoughLiquidityToWithdraw.selector);
        vault.withdraw(withdrawAmount, address(this), address(this));
    }

    // try to deposit and withdraw same amounts
    function test_Withdraw_FullWithdraw() public { }

    function test_Withdraw_Different_Queue_Order() public { }

    function test_DepositAndWithdraw_MultipleUsers() public { }
}

abstract contract VaultReallocate is VaultSharedSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    // --- Reallocate ---

    function test_Reallocate_AcrossAllMarkets() public {
        uint256 depositAmount = 10e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 2e18, 3e18, 5e18);

        vault.deposit(depositAmount, address(this));

        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        uint256 prevTotalAssets = vault.totalAssets();

        uint256 prevRsEthClaim = rsEthIonPool.balanceOf(address(vault));
        uint256 prevRswEthClaim = rswEthIonPool.balanceOf(address(vault));
        uint256 prevWeEthClaim = weEthIonPool.balanceOf(address(vault));

        int256 rswEthDiff = -1e18;
        int256 weEthDiff = -2e18;
        int256 rsEthDiff = 3e18;

        uint256 expNewRsEthClaim = uint256(int256(prevRsEthClaim) + rsEthDiff);
        uint256 expNewRswEthClaim = uint256(int256(prevRswEthClaim) + rswEthDiff);
        uint256 expNewWeEthClaim = uint256(int256(prevWeEthClaim) + weEthDiff);

        // withdraw 2 from pool2
        // withdraw 1 from pool3
        // deposit 3 to pool1
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: rswEthDiff });
        allocs[1] = Vault.MarketAllocation({ pool: weEthIonPool, assets: weEthDiff });
        allocs[2] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: rsEthDiff });

        vm.prank(ALLOCATOR);
        vault.reallocate(allocs);

        uint256 newTotalAssets = vault.totalAssets();

        assertApproxEqAbs(
            rsEthIonPool.balanceOf(address(vault)),
            expNewRsEthClaim,
            rsEthIonPool.supplyFactor() / RAY,
            "rsEth vault iToken claim"
        );
        assertApproxEqAbs(
            rswEthIonPool.balanceOf(address(vault)),
            expNewRswEthClaim,
            rswEthIonPool.supplyFactor() / RAY,
            "rswEth vault iToken claim"
        );
        assertApproxEqAbs(
            weEthIonPool.balanceOf(address(vault)),
            expNewWeEthClaim,
            weEthIonPool.supplyFactor() / RAY,
            "weEth vault iToken claim"
        );

        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "base asset balance");

        uint256 cumulativeRoundingError =
            rswEthIonPool.supplyFactor() / RAY + weEthIonPool.supplyFactor() / RAY + rsEthIonPool.supplyFactor() / RAY;
        assertApproxEqAbs(
            prevTotalAssets, newTotalAssets, cumulativeRoundingError, "total assets should remain the same"
        );
    }

    function test_Reallocate_ToSingleMarket_MaxWithdraw_MaxDeposit() public {
        uint256 depositAmount = 10e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rswEthIonPool, rsEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 2e18, 3e18, 5e18);

        vault.deposit(depositAmount, address(this));

        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        uint256 prevWeEthClaim = weEthIonPool.balanceOf(address(vault));
        uint256 prevRswEthClaim = rswEthIonPool.balanceOf(address(vault));
        uint256 prevRsEthClaim = rsEthIonPool.balanceOf(address(vault));
        uint256 expRswEthClaim = prevRswEthClaim + prevWeEthClaim + prevRsEthClaim;

        uint256 prevTotalAssets = vault.totalAssets();

        // withdraw 5 from rsEthIonPool
        // withdraw 2 from weEthIonPool
        // deposit 7 to rswEthIonPool
        int256 rsEthDiff = type(int256).min;
        int256 weEthDiff = type(int256).min;
        int256 rswEthDiff = type(int256).max;

        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: rsEthDiff });
        allocs[1] = Vault.MarketAllocation({ pool: weEthIonPool, assets: weEthDiff });
        allocs[2] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: rswEthDiff });

        vm.prank(ALLOCATOR);
        vault.reallocate(allocs);

        uint256 newTotalAssets = vault.totalAssets();

        assertEq(rsEthIonPool.balanceOf(address(vault)), 0, "rsEth vault iToken claim");
        assertEq(weEthIonPool.balanceOf(address(vault)), 0, "weEth vault iToken claim");
        assertApproxEqAbs(
            rswEthIonPool.balanceOf(address(vault)),
            expRswEthClaim,
            rswEthIonPool.supplyFactor() / RAY,
            "rswEth vault iToken claim"
        );

        assertApproxEqAbs(
            prevTotalAssets, newTotalAssets, rswEthIonPool.supplyFactor() / RAY, "total assets should remain the same"
        );
    }

    function test_Revert_Reallocate_AllocationCapExceeded() public {
        uint256 depositAmount = 10e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rswEthIonPool, rsEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 2e18, 3e18, 5e18);

        vault.deposit(depositAmount, address(this));

        updateAllocationCaps(vault, 3e18, type(uint256).max, type(uint256).max);

        uint256 prevTotalAssets = vault.totalAssets();

        uint256 weEthCurrentSupplied = weEthIonPool.balanceOf(address(vault));

        // tries to deposit 2e18 + 2e18 to 3e18 allocation cap
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: -1e18 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: -1e18 });
        allocs[2] = Vault.MarketAllocation({ pool: weEthIonPool, assets: 2e18 });

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(Vault.AllocationCapExceeded.selector, weEthCurrentSupplied + 2e18, 3e18));
        vault.reallocate(allocs);
    }

    function test_Revert_Reallocate_SupplyCapExceeded() public {
        uint256 depositAmount = 10e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rswEthIonPool, rsEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 2e18, 3e18, 5e18);

        vault.deposit(depositAmount, address(this));

        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateSupplyCaps(vault, 5e18, type(uint256).max, type(uint256).max);

        uint256 prevTotalAssets = vault.totalAssets();

        // tries to deposit 10e18 to 9e18 allocation cap
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: type(int256).min });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: type(int256).min });
        allocs[2] = Vault.MarketAllocation({ pool: weEthIonPool, assets: 4e18 });

        vm.prank(ALLOCATOR);
        vm.expectRevert(abi.encodeWithSelector(IIonPool.DepositSurpassesSupplyCap.selector, 4e18, 5e18));
        // vm.expectRevert(IIonPool.DepositSurpassesSupplyCap.selector);
        vault.reallocate(allocs);
    }
}

abstract contract VaultWithIdlePool is VaultSharedSetup {
    IIonPool[] marketsToAdd;
    uint256[] allocationCaps;

    function setUp() public virtual override {
        super.setUp();

        vault = new Vault(
            BASE_ASSET, FEE_RECIPIENT, ZERO_FEES, "Ion Vault Token", "IVT", INITIAL_DELAY, VAULT_ADMIN, emptyMarketsArgs
        );

        BASE_ASSET.approve(address(vault), type(uint256).max);

        marketsToAdd = new IIonPool[](4);
        marketsToAdd[0] = weEthIonPool;
        marketsToAdd[1] = IDLE;
        marketsToAdd[2] = rsEthIonPool;
        marketsToAdd[3] = rswEthIonPool;

        allocationCaps = new uint256[](4);
        allocationCaps[0] = 10e18;
        allocationCaps[1] = 20e18;
        allocationCaps[2] = 30e18;
        allocationCaps[3] = 40e18;

        vm.startPrank(vault.defaultAdmin());

        vault.grantRole(vault.OWNER_ROLE(), OWNER);
        vault.grantRole(vault.ALLOCATOR_ROLE(), OWNER);
        vault.grantRole(vault.ALLOCATOR_ROLE(), ALLOCATOR);

        vm.stopPrank();

        vm.prank(OWNER);
        vault.addSupportedMarkets(marketsToAdd, allocationCaps, marketsToAdd, marketsToAdd);
    }

    function test_Deposit_AllMarkets_FirstDeposit() public {
        uint256 depositAmount = 70e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        uint256 weEthIonPoolSF = weEthIonPool.supplyFactor();
        uint256 rsEthIonPoolSF = rsEthIonPool.supplyFactor();
        uint256 rswEthIonPoolSF = rswEthIonPool.supplyFactor();

        vault.deposit(depositAmount, address(this));

        // weEthIonPool should be full at 10e18
        // IDLE should be full at 20e18
        // rsEthIonPool should be full at 30e18
        // rswEthIonPool should be at 10e18
        assertLe(
            10e18 - weEthIonPool.balanceOf(address(vault)), postDepositClaimRE(10e18, weEthIonPoolSF), "weEthIonPool"
        );
        assertEq(BASE_ASSET.balanceOf(address(vault)), 20e18, "IDLE");
        assertLe(
            30e18 - rsEthIonPool.balanceOf(address(vault)), postDepositClaimRE(30e18, rsEthIonPoolSF), "rsEthIonPool"
        );
        assertLe(
            10e18 - rswEthIonPool.balanceOf(address(vault)), postDepositClaimRE(10e18, rswEthIonPoolSF), "rswEthIonPool"
        );
        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "user balance");
    }

    function test_Deposit_AllMarkets_SecondDeposit() public { }

    function test_Mint_AllMarkets_FirstMint() public {
        uint256 sharesToMint = 70e18;

        uint256 weEthIonPoolSF = weEthIonPool.supplyFactor();
        uint256 rsEthIonPoolSF = rsEthIonPool.supplyFactor();
        uint256 rswEthIonPoolSF = rswEthIonPool.supplyFactor();

        uint256 expectedDepositAmount = vault.previewMint(sharesToMint);
        setERC20Balance(address(BASE_ASSET), address(this), expectedDepositAmount);

        vault.mint(sharesToMint, address(this));

        uint256 remainingAssets = expectedDepositAmount;

        uint256 expectedWeEthIonPoolClaim = Math.min(remainingAssets, vault.caps(weEthIonPool));
        remainingAssets -= expectedWeEthIonPoolClaim;

        uint256 expectedIdleClaim = Math.min(remainingAssets, vault.caps(IDLE));
        remainingAssets -= expectedIdleClaim;

        uint256 expectedRsEthIonPoolClaim = Math.min(remainingAssets, vault.caps(rsEthIonPool));
        remainingAssets -= expectedRsEthIonPoolClaim;

        uint256 expectedRswEthIonPoolClaim = Math.min(remainingAssets, vault.caps(rswEthIonPool));
        remainingAssets -= expectedRswEthIonPoolClaim;

        assertEq(remainingAssets, 0, "test variables");
        assertLe(
            expectedWeEthIonPoolClaim - weEthIonPool.balanceOf(address(vault)),
            postDepositClaimRE(expectedWeEthIonPoolClaim, weEthIonPoolSF),
            "weEthIonPool"
        );
        assertEq(BASE_ASSET.balanceOf(address(vault)), expectedIdleClaim, "IDLE");
        assertLe(
            expectedRsEthIonPoolClaim - rsEthIonPool.balanceOf(address(vault)),
            postDepositClaimRE(expectedWeEthIonPoolClaim, rsEthIonPoolSF),
            "rsEthIonPool"
        );
        assertLe(
            expectedRswEthIonPoolClaim - rswEthIonPool.balanceOf(address(vault)),
            postDepositClaimRE(expectedRswEthIonPoolClaim, rswEthIonPoolSF),
            "rswEthIonPool"
        );
        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "user balance");
    }

    function test_Mint_AllMarkets_SecondMint() public { }

    function test_PartialWithdraw() public {
        uint256 depositAmount = 70e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);
        vault.deposit(depositAmount, address(this));

        // expected values
        uint256 prevTotalAssets = vault.totalAssets();
        uint256 supplyFactor = rsEthIonPool.supplyFactor();

        uint256 weEthIonPoolClaim = weEthIonPool.balanceOf(address(vault));
        uint256 idleClaim = BASE_ASSET.balanceOf(address(vault));
        uint256 rsEthIonPoolClaim = rsEthIonPool.balanceOf(address(vault));
        uint256 rswEthIonPoolClaim = rswEthIonPool.balanceOf(address(vault));

        uint256 withdrawAmount = 40e18;

        uint256 expectedTotalAssets = prevTotalAssets - withdrawAmount;

        uint256 remainingAssets = withdrawAmount;

        uint256 weEthIonPoolWithdraw = Math.min(weEthIonPoolClaim, remainingAssets);
        remainingAssets -= weEthIonPoolWithdraw; // about 10 out of 10

        uint256 idleWithdraw = Math.min(idleClaim, remainingAssets);
        remainingAssets -= idleWithdraw; // about 20 out of 20

        uint256 rsEthIonPoolWithdraw = Math.min(rsEthIonPoolClaim, remainingAssets);
        remainingAssets -= rsEthIonPoolWithdraw; // about 10 out of 30

        // uint256 rswEthIonPoolWithdraw = Math.min(rswEthIonPoolClaim, remainingAssets);
        // remainingAssets -= rswEthIonPoolWithdraw;

        assertEq(remainingAssets, 0, "test variables");

        vault.withdraw(withdrawAmount, address(this), address(this));

        // vault total assets decreases by withdraw amount + rounding error
        assertLe(
            expectedTotalAssets - vault.totalAssets(),
            postDepositClaimRE(withdrawAmount, supplyFactor),
            "vault total assets"
        );
        assertEq(weEthIonPool.balanceOf(address(vault)), 0, "weEthIonPool claim");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "idle deposits");
        assertLt(
            (rsEthIonPoolClaim - rsEthIonPoolWithdraw) - rsEthIonPool.balanceOf(address(vault)),
            postDepositClaimRE(withdrawAmount, supplyFactor),
            "rsEthIonPool claim"
        );
        assertEq(rswEthIonPool.balanceOf(address(vault)), rswEthIonPoolClaim, "rswEthIonPool claim");

        // user gains withdrawn balance
        assertEq(BASE_ASSET.balanceOf(address(this)), withdrawAmount, "user base asset balance");
    }

    function test_MaxWithdraw() public {
        uint256 depositAmount = 70e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);
        vault.deposit(depositAmount, address(this));

        uint256 withdrawAmount = vault.maxWithdraw(address(this));
        vault.withdraw(withdrawAmount, address(this), address(this));

        assertEq(vault.totalAssets(), 0, "vault total assets");
        assertEq(vault.totalSupply(), 0, "vault total shares");

        assertEq(BASE_ASSET.balanceOf(address(this)), withdrawAmount, "user base asset balance");
        assertEq(vault.balanceOf(address(this)), 0, "user shares balance");
    }

    function test_MaxRedeem() public {
        uint256 depositAmount = 70e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);
        vault.deposit(depositAmount, address(this));

        // all deposits are available to be withdrawn.
        uint256 redeemAmount = vault.maxRedeem(address(this));

        uint256 withdrawnAssets = vault.redeem(redeemAmount, address(this), address(this));

        uint256 weEthRoundingError = (weEthIonPool.supplyFactor()) / RAY + 1;
        uint256 rsEthRoundingError = (rsEthIonPool.supplyFactor()) / RAY + 1;
        uint256 rswEthRoundingError = (rswEthIonPool.supplyFactor()) / RAY + 1;
        uint256 roundingError = weEthRoundingError + rsEthRoundingError + rswEthRoundingError;

        // _maxWithdraw rounds down inside the `IonPool` to calculate the claims
        // and the shares conversion rounds down again.
        assertLe(vault.totalAssets(), roundingError, "vault total assets");
        assertLe(vault.totalSupply(), roundingError, "vault total shares");

        assertEq(withdrawnAssets, BASE_ASSET.balanceOf(address(this)), "user base asset balance");
        assertLe(vault.balanceOf(address(this)), 1, "user shares balance");
    }

    function test_Reallocate_DepositToIdle() public {
        uint256 depositAmount = 70e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);
        vault.deposit(depositAmount, address(this));

        IIonPool[] memory ionPoolToUpdate = new IIonPool[](1);
        ionPoolToUpdate[0] = IDLE;
        uint256[] memory newAllocationCaps = new uint256[](1);
        newAllocationCaps[0] = 50e18;

        vm.prank(OWNER);
        vault.updateAllocationCaps(ionPoolToUpdate, newAllocationCaps);

        // 10 weEth 20 idle 30 rsEth 10 rswEth
        uint256 prevWeEthClaim = weEthIonPool.balanceOf(address(vault));
        uint256 prevIdleClaim = BASE_ASSET.balanceOf(address(vault));
        uint256 prevRsEthClaim = rsEthIonPool.balanceOf(address(vault));
        uint256 prevRswEthClaim = rswEthIonPool.balanceOf(address(vault));

        uint256 weEthSF = weEthIonPool.supplyFactor();
        uint256 rsEthSF = rsEthIonPool.supplyFactor();

        int256 weEthDiff = -1e18;
        int256 rsEthDiff = -2e18;
        int256 idleDiff = 3e18;

        uint256 expectedWeEthClaim = uint256(int256(prevWeEthClaim) + weEthDiff);
        uint256 expectedIdleClaim = uint256(int256(prevIdleClaim) + idleDiff);
        uint256 expectedRsEthClaim = uint256(int256(prevRsEthClaim) + rsEthDiff);

        // withdraw 5 from weEth, withdraw 7 from idle, deposit 12 to rswEth
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: weEthIonPool, assets: weEthDiff });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: rsEthDiff });
        allocs[2] = Vault.MarketAllocation({ pool: IDLE, assets: idleDiff });

        vm.prank(ALLOCATOR);
        vault.reallocate(allocs);

        assertLt(
            expectedWeEthClaim - weEthIonPool.balanceOf(address(vault)), postDepositClaimRE(0, weEthSF), "weEthIonPol"
        );
        assertEq(BASE_ASSET.balanceOf(address(vault)), expectedIdleClaim, "IDLE");
        assertLt(
            expectedRsEthClaim - rsEthIonPool.balanceOf(address(vault)), postDepositClaimRE(0, rsEthSF), "rswEthIonPol"
        );
        assertEq(prevRswEthClaim, rswEthIonPool.balanceOf(address(vault)), "rswEthIonPool");
    }

    function test_Reallocate_WithdrawFromIdle() public {
        uint256 depositAmount = 70e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);
        vault.deposit(depositAmount, address(this));

        // 10 weEth 20 idle 30 rsEth 10 rswEth
        uint256 prevWeEthClaim = weEthIonPool.balanceOf(address(vault));
        uint256 prevIdleClaim = BASE_ASSET.balanceOf(address(vault));
        uint256 prevRsEthClaim = rsEthIonPool.balanceOf(address(vault));
        uint256 prevRswEthClaim = rswEthIonPool.balanceOf(address(vault));

        uint256 weEthSF = weEthIonPool.supplyFactor();
        uint256 rswEthSF = rswEthIonPool.supplyFactor();

        int256 weEthDiff = -5e18;
        int256 idleDiff = -7e18;
        int256 rswEthDiff = 12e18;

        uint256 expectedWeEthClaim = uint256(int256(prevWeEthClaim) + weEthDiff);
        uint256 expectedIdleClaim = uint256(int256(prevIdleClaim) + idleDiff);
        uint256 expectedRswEthClaim = uint256(int256(prevRswEthClaim) + rswEthDiff);

        // withdraw 5 from weEth, withdraw 7 from idle, deposit 12 to rswEth
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: weEthIonPool, assets: weEthDiff });
        allocs[1] = Vault.MarketAllocation({ pool: IDLE, assets: idleDiff });
        allocs[2] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: rswEthDiff });

        vm.prank(ALLOCATOR);
        vault.reallocate(allocs);

        assertLt(
            expectedWeEthClaim - weEthIonPool.balanceOf(address(vault)), postDepositClaimRE(0, weEthSF), "weEthIonPol"
        );
        assertEq(BASE_ASSET.balanceOf(address(vault)), expectedIdleClaim, "IDLE");
        assertLt(
            expectedRswEthClaim - rswEthIonPool.balanceOf(address(vault)),
            postDepositClaimRE(0, rswEthSF),
            "rswEthIonPol"
        );
        assertEq(prevRsEthClaim, rsEthIonPool.balanceOf(address(vault)), "rsEthIonPool");
    }
}

contract VaultERC4626ExternalViews is VaultSharedSetup {
    function setUp() public override {
        super.setUp();
    }

    // --- Max ---
    // Get max and submit max transactions

    function test_MaxDepositView_AllocationAndSupplyCaps() public {
        uint256 maxDeposit = vault.maxDeposit(NULL);
        assertEq(maxDeposit, 0, "initial max deposit");

        uint256[] memory allocationCaps = new uint256[](3);
        allocationCaps[0] = 10e18;
        allocationCaps[1] = 20e18;
        allocationCaps[2] = 30e18;

        vm.prank(OWNER);
        vault.updateAllocationCaps(markets, allocationCaps);

        maxDeposit = vault.maxDeposit(NULL);
        assertEq(maxDeposit, 60e18, "new max deposit after update allocation cap");

        // change IonPool supply cap
        weEthIonPool.updateSupplyCap(5e18); // 10 allocation cap > 5 supply cap

        maxDeposit = vault.maxDeposit(NULL);
        assertEq(maxDeposit, 55e18, "max deposit after update supply cap");
    }

    function test_MaxDeposit_AfterDeposits() public { }

    function test_MaxMint_MintAmount() public {
        uint256[] memory allocationCaps = new uint256[](3);
        allocationCaps[0] = 10e18;
        allocationCaps[1] = 20e18;
        allocationCaps[2] = 30e18;

        vm.prank(OWNER);
        vault.updateAllocationCaps(markets, allocationCaps);

        uint256 maxMintShares = vault.maxMint(NULL);
        console2.log("maxMintShares: ", maxMintShares);

        setERC20Balance(address(BASE_ASSET), address(this), 60e18);
        vault.mint(maxMintShares, address(this));

        uint256 resultingShares = vault.balanceOf(address(this));

        uint256 maxWithdrawableAssets = vault.previewRedeem(resultingShares);
        uint256 maxRedeemableShares = vault.previewWithdraw(maxWithdrawableAssets);

        assertEq(resultingShares, 60e18, "resulting shares");
        assertEq(maxWithdrawableAssets, 60e18, "resulting claim");
        assertEq(maxRedeemableShares, 60e18, "redeemable shares");
    }

    function test_MaxWithdraw() public { }

    function test_MaxRedeem() public { }

    // --- Previews ---

    // Check the difference between preview and actual

    function test_PreviewDeposit() public { }

    function test_PreviewMint() public { }

    function test_PreviewWithdraw() public { }

    function test_PreviewRedeem() public { }
}

contract VaultInflationAttack is VaultSharedSetup {
    function setUp() public override {
        super.setUp();
    }

    /**
     * Starting Attacker Balance: 11e18 + 10
     * Attacker Mint: 10 shares
     * Attacker Donation: 11e18
     * Alice Deposit: 1e18
     * Alice Shares Minted:
     *
     * How much did the attacker lose during the donation?
     * Attacker Donated 11e18,
     */
    function test_InflationAttackNotProfitable() public {
        IIonPool[] memory market = new IIonPool[](1);
        market[0] = IDLE;

        uint256[] memory allocationCaps = new uint256[](1);
        allocationCaps[0] = type(uint256).max;

        IIonPool[] memory queue = new IIonPool[](4);
        queue[0] = IDLE;
        queue[1] = weEthIonPool;
        queue[2] = rsEthIonPool;
        queue[3] = rswEthIonPool;

        vm.prank(OWNER);
        vault.addSupportedMarkets(market, allocationCaps, queue, queue);

        uint256 donationAmt = 11e18;
        uint256 mintAmt = 10;

        // fund attacker
        setERC20Balance(address(BASE_ASSET), address(this), donationAmt + mintAmt);

        uint256 initialAssetBalance = BASE_ASSET.balanceOf(address(this));
        console2.log("attacker balance before : ");
        console2.log(initialAssetBalance);

        vault.mint(mintAmt, address(this));
        uint256 attackerClaimAfterMint = vault.previewRedeem(vault.balanceOf(address(this)));

        console2.log("attackerClaimAfterMint: ");
        console2.log(attackerClaimAfterMint);

        console2.log("donationAmt: ");
        console2.log(donationAmt);

        // donate to inflate exchange rate by increasing `totalAssets`
        IERC20(address(BASE_ASSET)).transfer(address(vault), donationAmt);

        // how much of this donation was captured by the virtual shares on the vault?
        uint256 attackerClaimAfterDonation = vault.previewRedeem(vault.balanceOf(address(this)));

        console2.log("attackerClaimAfterDonation: ");
        console2.log(attackerClaimAfterDonation);

        uint256 lossFromDonation = attackerClaimAfterMint + donationAmt - attackerClaimAfterDonation;

        console2.log("loss from donation: ");
        console2.log(lossFromDonation);

        address alice = address(0xabcd);
        setERC20Balance(address(BASE_ASSET), alice, 10e18 + 10);

        vm.startPrank(alice);
        IERC20(address(BASE_ASSET)).approve(address(vault), 1e18);
        vault.deposit(1e18, alice);
        vm.stopPrank();

        // Alice gained zero shares due to exchange rate inflation
        uint256 aliceShares = vault.balanceOf(alice);
        console.log("alice must lose all her shares : ");
        console.log(aliceShares);

        // How much of alice's deposits were captured by the attacker's shares?
        uint256 attackerClaimAfterAlice = vault.previewRedeem(vault.balanceOf(address(this)));
        uint256 attackerGainFromAlice = attackerClaimAfterAlice - attackerClaimAfterDonation;
        console2.log("attackerGainFromAlice: ");
        console2.log(attackerGainFromAlice);

        vault.redeem(vault.balanceOf(address(this)) - 3, address(this), address(this));
        uint256 afterAssetBalance = BASE_ASSET.balanceOf(address(this));

        console.log("attacker balance after : ");
        console.log(afterAssetBalance);

        assertLe(attackerGainFromAlice, lossFromDonation, "attack must not be profitable");
        assertLe(afterAssetBalance, initialAssetBalance, "attacker must not be profitable");
    }
}

contract VaultDeposit_WithoutSupplyFactor is VaultDeposit {
    function setUp() public override(VaultDeposit) {
        super.setUp();
    }
}

contract VaultDeposit_WithSupplyFactor is VaultDeposit {
    function setUp() public override(VaultDeposit) {
        super.setUp();
        withSupplyFactor();
    }
}

contract VaultDeposit_WithInflatedSupplyFactor is VaultDeposit {
    function setUp() public override(VaultDeposit) {
        super.setUp();
        withInflatedSupplyFactor();
    }
}

contract VaultWithdraw_WithoutSupplyFactor is VaultWithdraw {
    function setUp() public override(VaultWithdraw) {
        super.setUp();
    }
}

contract VaultWithdraw_WithSupplyFactor is VaultWithdraw {
    function setUp() public override(VaultWithdraw) {
        super.setUp();
        withSupplyFactor();
    }
}

contract VaultWithdraw_WithInflatedSupplyFactor is VaultWithdraw {
    function setUp() public override(VaultWithdraw) {
        super.setUp();
        withInflatedSupplyFactor();
    }
}

contract VaultReallocate_WithoutSupplyFactor is VaultReallocate {
    function setUp() public override(VaultReallocate) {
        super.setUp();
    }
}

contract VaultReallocate_WithSupplyFactor is VaultReallocate {
    function setUp() public override(VaultReallocate) {
        super.setUp();
        withSupplyFactor();
    }
}

contract VaultReallocate_WithInflatedSupplyFactor is VaultReallocate {
    function setUp() public override(VaultReallocate) {
        super.setUp();
        withInflatedSupplyFactor();
    }
}

contract VaultWithIdlePool_WithoutSupplyFactor is VaultWithIdlePool {
    function setUp() public override(VaultWithIdlePool) {
        super.setUp();
    }
}

contract VaultWithIdlePool_WithSupplyFactor is VaultWithIdlePool {
    function setUp() public override(VaultWithIdlePool) {
        super.setUp();
        withSupplyFactor();
    }
}

contract VaultWithIdlePool_WithInflatedSupplyFactor is VaultWithIdlePool {
    function setUp() public override(VaultWithIdlePool) {
        super.setUp();
        withInflatedSupplyFactor();
    }
}
