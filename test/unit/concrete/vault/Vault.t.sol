// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultSharedSetup } from "./../../../helpers/VaultSharedSetup.sol";

import { WadRayMath, RAY } from "./../../../../src/libraries/math/WadRayMath.sol";
import { Vault } from "./../../../../src/vault/Vault.sol";
import { IonPool } from "./../../../../src/IonPool.sol";
import { IIonPool } from "./../../../../src/interfaces/IIonPool.sol";
import { IonLens } from "./../../../../src/periphery/IonLens.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

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
            ionLens, BASE_ASSET, FEE_RECIPIENT, ZERO_FEES, "Ion Vault Token", "IVT", INITIAL_DELAY, VAULT_ADMIN
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
            ionLens, BASE_ASSET, FEE_RECIPIENT, ZERO_FEES, "Ion Vault Token", "IVT", INITIAL_DELAY, VAULT_ADMIN
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

        vm.expectRevert(Vault.InvalidQueueLength.selector);
        vault.updateSupplyQueue(invalidLengthQueue);

        IIonPool[] memory zeroAddressQueue = new IIonPool[](3);

        vm.expectRevert(Vault.InvalidQueueMarketNotSupported.selector);
        vault.updateSupplyQueue(zeroAddressQueue);

        IIonPool[] memory notSupportedQueue = new IIonPool[](3);
        notSupportedQueue[0] = rsEthIonPool;
        notSupportedQueue[1] = rswEthIonPool;
        notSupportedQueue[2] = IIonPool(address(uint160(uint256(keccak256("address not in supported markets")))));

        vm.expectRevert(Vault.InvalidQueueMarketNotSupported.selector);
        vault.updateSupplyQueue(notSupportedQueue);
    }

    function test_UpdateWithdrawQueue() public { }

    function test_Revert_UpdateWithdrawQUeue() public { }

    function test_Revert_DuplicateIonPoolArray() public { }
}

contract VaultDeposit is VaultSharedSetup {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_Deposit_WithoutSupplyCap_WithoutAllocationCap() public {
        uint256 depositAmount = 1e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rsEthIonPool, rswEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        uint256 prevWeEthShares = weEthIonPool.balanceOf(address(vault));

        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");
        assertEq(
            weEthIonPool.getUnderlyingClaimOf(address(vault)),
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

        uint256 prevWeEthShares = weEthIonPool.balanceOf(address(vault));
        uint256 prevRsEthShares = rsEthIonPool.balanceOf(address(vault));
        uint256 prevRswEthShares = rswEthIonPool.balanceOf(address(vault));

        // 3e18 gets spread out equally amongst the three pools
        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        assertEq(
            weEthIonPool.getUnderlyingClaimOf(address(vault)),
            claimAfterDeposit(prevWeEthShares, 1e18, weEthIonPool.supplyFactor()),
            "weEth vault iToken claim"
        );
        assertEq(
            rsEthIonPool.getUnderlyingClaimOf(address(vault)),
            claimAfterDeposit(prevRsEthShares, 1e18, rsEthIonPool.supplyFactor()),
            "rsEth vault iToken claim"
        );
        assertEq(
            rswEthIonPool.getUnderlyingClaimOf(address(vault)),
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

        uint256 prevWeEthShares = weEthIonPool.balanceOf(address(vault));
        uint256 prevRsEthShares = rsEthIonPool.balanceOf(address(vault));
        uint256 prevRswEthShares = rswEthIonPool.balanceOf(address(vault));

        // 3e18 gets spread out equally amongst the three pools
        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        assertEq(
            weEthIonPool.getUnderlyingClaimOf(address(vault)),
            claimAfterDeposit(prevWeEthShares, 2e18, weEthIonPool.supplyFactor()),
            "weEth vault iToken claim"
        );
        assertEq(
            rsEthIonPool.getUnderlyingClaimOf(address(vault)),
            claimAfterDeposit(prevRsEthShares, 3e18, rsEthIonPool.supplyFactor()),
            "rsEth vault iToken claim"
        );
        assertEq(
            rswEthIonPool.getUnderlyingClaimOf(address(vault)),
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

        uint256 prevWeEthShares = weEthIonPool.balanceOf(address(vault));
        uint256 prevRsEthShares = rsEthIonPool.balanceOf(address(vault));
        uint256 prevRswEthShares = rswEthIonPool.balanceOf(address(vault));

        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        assertEq(
            weEthIonPool.getUnderlyingClaimOf(address(vault)),
            claimAfterDeposit(prevWeEthShares, 2e18, weEthIonPool.supplyFactor()),
            "weEth vault iToken claim"
        );
        assertEq(
            rsEthIonPool.getUnderlyingClaimOf(address(vault)),
            claimAfterDeposit(prevRsEthShares, 3e18, rsEthIonPool.supplyFactor()),
            "rsEth vault iToken claim"
        );
        assertEq(
            rswEthIonPool.getUnderlyingClaimOf(address(vault)),
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

    function test_Mint_WithIdle() public { }
}

contract VaultWithdraw is VaultSharedSetup {
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

        assertEq(
            vault.totalAssets(), rsEthIonPool.getUnderlyingClaimOf(address(vault)), "single market for total assets"
        );
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

        assertEq(rsEthIonPool.getUnderlyingClaimOf(address(vault)), 0, "vault pool1 balance");
        assertEq(rswEthIonPool.getUnderlyingClaimOf(address(vault)), 0, "vault pool2 balance");
        assertLe(
            expectedNewTotalAssets - weEthIonPool.getUnderlyingClaimOf(address(vault)),
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

    // try to deposit and withdraw same amounts
    function test_Withdraw_FullWithdraw() public { }

    function test_Withdraw_Different_Queue_Order() public { }

    function test_DepositAndWithdraw_MultipleUsers() public { }

    function test_Revert_Withdraw() public { }
}

contract VaultReallocate is VaultSharedSetup {
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

        uint256 prevRsEthClaim = rsEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 prevRswEthClaim = rswEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 prevWeEthClaim = weEthIonPool.getUnderlyingClaimOf(address(vault));

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
            rsEthIonPool.getUnderlyingClaimOf(address(vault)),
            expNewRsEthClaim,
            rsEthIonPool.supplyFactor() / RAY,
            "rsEth vault iToken claim"
        );
        assertApproxEqAbs(
            rswEthIonPool.getUnderlyingClaimOf(address(vault)),
            expNewRswEthClaim,
            rswEthIonPool.supplyFactor() / RAY,
            "rswEth vault iToken claim"
        );
        assertApproxEqAbs(
            weEthIonPool.getUnderlyingClaimOf(address(vault)),
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

        uint256 prevWeEthClaim = weEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 prevRswEthClaim = rswEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 prevRsEthClaim = rsEthIonPool.getUnderlyingClaimOf(address(vault));
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

        assertEq(rsEthIonPool.getUnderlyingClaimOf(address(vault)), 0, "rsEth vault iToken claim");
        assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), 0, "weEth vault iToken claim");
        assertApproxEqAbs(
            rswEthIonPool.getUnderlyingClaimOf(address(vault)),
            expRswEthClaim,
            rswEthIonPool.supplyFactor() / RAY,
            "rswEth vault iToken claim"
        );

        assertApproxEqAbs(
            prevTotalAssets, newTotalAssets, rswEthIonPool.supplyFactor() / RAY, "total assets should remain the same"
        );
    }

    function test_Reallocate_WithIdleAsset() public {
        //
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

        // tries to deposit 10e18 to 9e18 allocation cap
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: -1e18 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: -1e18 });
        allocs[2] = Vault.MarketAllocation({ pool: weEthIonPool, assets: 2e18 });

        vm.prank(ALLOCATOR);
        vm.expectRevert(Vault.AllocationCapExceeded.selector);
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

contract VaultWithIdlePool is VaultSharedSetup {
    IIonPool[] marketsToAdd;
    uint256[] allocationCaps;

    function setUp() public virtual override {
        super.setUp();

        vault = new Vault(
            ionLens, BASE_ASSET, FEE_RECIPIENT, ZERO_FEES, "Ion Vault Token", "IVT", INITIAL_DELAY, VAULT_ADMIN
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
            10e18 - weEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(10e18, weEthIonPoolSF),
            "weEthIonPool"
        );
        assertEq(BASE_ASSET.balanceOf(address(vault)), 20e18, "IDLE");
        assertLt(
            30e18 - rsEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(30e18, rsEthIonPoolSF),
            "rsEthIonPool"
        );
        assertLt(
            10e18 - rswEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(10e18, rswEthIonPoolSF),
            "rswEthIonPool"
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
            expectedWeEthIonPoolClaim - weEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(expectedWeEthIonPoolClaim, weEthIonPoolSF),
            "weEthIonPool"
        );
        assertEq(BASE_ASSET.balanceOf(address(vault)), expectedIdleClaim, "IDLE");
        assertLt(
            expectedRsEthIonPoolClaim - rsEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(expectedWeEthIonPoolClaim, rsEthIonPoolSF),
            "rsEthIonPool"
        );
        assertLt(
            expectedRswEthIonPoolClaim - rswEthIonPool.getUnderlyingClaimOf(address(vault)),
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

        uint256 weEthIonPoolClaim = weEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 idleClaim = BASE_ASSET.balanceOf(address(vault));
        uint256 rsEthIonPoolClaim = rsEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 rswEthIonPoolClaim = rswEthIonPool.getUnderlyingClaimOf(address(vault));

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
        assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), 0, "weEthIonPool claim");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "idle deposits");
        assertLt(
            (rsEthIonPoolClaim - rsEthIonPoolWithdraw) - rsEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(withdrawAmount, supplyFactor),
            "rsEthIonPool claim"
        );
        assertEq(rswEthIonPool.getUnderlyingClaimOf(address(vault)), rswEthIonPoolClaim, "rswEthIonPool claim");

        // user gains withdrawn balance
        assertEq(BASE_ASSET.balanceOf(address(this)), withdrawAmount, "user base asset balance");
    }

    function test_FullWithdraw() public {
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

    function test_Redeem() public { }

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
        uint256 prevWeEthClaim = weEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 prevIdleClaim = BASE_ASSET.balanceOf(address(vault));
        uint256 prevRsEthClaim = rsEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 prevRswEthClaim = rswEthIonPool.getUnderlyingClaimOf(address(vault));

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
            expectedWeEthClaim - weEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(0, weEthSF),
            "weEthIonPol"
        );
        assertEq(BASE_ASSET.balanceOf(address(vault)), expectedIdleClaim, "IDLE");
        assertLt(
            expectedRsEthClaim - rsEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(0, rsEthSF),
            "rswEthIonPol"
        );
        assertEq(prevRswEthClaim, rswEthIonPool.getUnderlyingClaimOf(address(vault)), "rswEthIonPool");
    }

    function test_Reallocate_WithdrawFromIdle() public {
        uint256 depositAmount = 70e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);
        vault.deposit(depositAmount, address(this));

        // 10 weEth 20 idle 30 rsEth 10 rswEth
        uint256 prevWeEthClaim = weEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 prevIdleClaim = BASE_ASSET.balanceOf(address(vault));
        uint256 prevRsEthClaim = rsEthIonPool.getUnderlyingClaimOf(address(vault));
        uint256 prevRswEthClaim = rswEthIonPool.getUnderlyingClaimOf(address(vault));

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
            expectedWeEthClaim - weEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(0, weEthSF),
            "weEthIonPol"
        );
        assertEq(BASE_ASSET.balanceOf(address(vault)), expectedIdleClaim, "IDLE");
        assertLt(
            expectedRswEthClaim - rswEthIonPool.getUnderlyingClaimOf(address(vault)),
            postDepositClaimRE(0, rswEthSF),
            "rswEthIonPol"
        );
        assertEq(prevRsEthClaim, rsEthIonPool.getUnderlyingClaimOf(address(vault)), "rsEthIonPool");
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
    }
}

contract VaultDeposit_WithInflatedSupplyFactor is VaultDeposit {
    function setUp() public override(VaultDeposit) {
        super.setUp();
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
    }
}

contract VaultWithdraw_WithInflatedSupplyFactor is VaultWithdraw {
    function setUp() public override(VaultWithdraw) {
        super.setUp();
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
    }
}

contract VaultReallocate_WithInflatedSupplyFactor is VaultReallocate {
    function setUp() public override(VaultReallocate) {
        super.setUp();
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
    }
}

contract VaultWithIdlePool_WithInflatedSupplyFactor is VaultWithIdlePool {
    function setUp() public override(VaultWithIdlePool) {
        super.setUp();
    }
}
