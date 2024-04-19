// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultSharedSetup } from "./../../helpers/VaultSharedSetup.sol";

import { WadRayMath, RAY } from "./../../../src/libraries/math/WadRayMath.sol";
import { Vault } from "./../../../src/vault/Vault.sol";
import { IonPool } from "./../../../src/IonPool.sol";
import { IIonPool } from "./../../../src/interfaces/IIonPool.sol";
import { IonLens } from "./../../../src/periphery/IonLens.sol";
import { GemJoin } from "./../../../src/join/GemJoin.sol";
import { YieldOracle } from "./../../../src/YieldOracle.sol";
import { IYieldOracle } from "./../../../src/interfaces/IYieldOracle.sol";
import { InterestRate } from "./../../../src/InterestRate.sol";
import { Whitelist } from "./../../../src/Whitelist.sol";
import { ProxyAdmin } from "./../../../src/admin/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "./../../../src/admin/TransparentUpgradeableProxy.sol";
import { WSTETH_ADDRESS } from "./../../../src/Constants.sol";
import { IonPoolSharedSetup, IonPoolExposed, MockSpotOracle } from "../../helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "../../helpers/ERC20PresetMinterPauser.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";
// import { StdStorage, stdStorage } from "../../../../lib/forge-safe/lib/forge-std/src/StdStorage.sol";

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

using EnumerableSet for EnumerableSet.AddressSet;
using WadRayMath for uint256;
using Math for uint256;

address constant VAULT_OWNER = address(1);
address constant FEE_RECIPIENT = address(2);

contract VaultSetUpTest is VaultSharedSetup {
    function setUp() public override {
        super.setUp();
    }

    function test_AddSupportedMarketsSeparately() public {
        Vault emptyVault = new Vault(VAULT_OWNER, FEE_RECIPIENT, BASE_ASSET, ionLens, "Ion Vault Token", "IVT");
        vm.startPrank(emptyVault.owner());

        IIonPool[] memory market1 = new IIonPool[](1);
        market1[0] = weEthIonPool;
        IIonPool[] memory market2 = new IIonPool[](1);
        market2[0] = rsEthIonPool;
        IIonPool[] memory market3 = new IIonPool[](1);
        market3[0] = rswEthIonPool;

        emptyVault.addSupportedMarkets(market1);
        address[] memory supportedMarkets1 = emptyVault.getSupportedMarkets();
        console2.log("supportedMarkets1[0]: ", supportedMarkets1[0]);
        assertEq(supportedMarkets1.length, 1, "supported markets length one");
        assertEq(supportedMarkets1[0], address(weEthIonPool), "first supported markets address");

        emptyVault.addSupportedMarkets(market2);
        address[] memory supportedMarkets2 = emptyVault.getSupportedMarkets();
        assertEq(supportedMarkets2.length, 2, "supported markets length two");
        assertEq(supportedMarkets2[1], address(rsEthIonPool), "second supported markets address");

        emptyVault.addSupportedMarkets(market3);
        address[] memory supportedMarkets3 = emptyVault.getSupportedMarkets();
        assertEq(supportedMarkets3.length, 3, "supported markets length three");
        assertEq(supportedMarkets3[2], address(rswEthIonPool), "third supported markets address");
    }

    function test_AddSupportedMarketsTogether() public {
        Vault emptyVault = new Vault(VAULT_OWNER, FEE_RECIPIENT, BASE_ASSET, ionLens, "Ion Vault Token", "IVT");
        vm.startPrank(emptyVault.owner());
        IIonPool[] memory markets = new IIonPool[](3);
        markets[0] = weEthIonPool;
        markets[1] = rsEthIonPool;
        markets[2] = rswEthIonPool;

        emptyVault.addSupportedMarkets(markets);
        address[] memory supportedMarkets = emptyVault.getSupportedMarkets();

        assertEq(supportedMarkets.length, 3, "supported markets length");
        assertEq(supportedMarkets[0], address(weEthIonPool), "first supported markets address");
        assertEq(supportedMarkets[1], address(rsEthIonPool), "second supported markets address");
        assertEq(supportedMarkets[2], address(rswEthIonPool), "third supported markets address");
    }

    function test_UpdateSupplyQueue() public {
        IIonPool[] memory supplyQueue = new IIonPool[](3);
        supplyQueue[0] = rsEthIonPool;
        supplyQueue[1] = rswEthIonPool;
        supplyQueue[2] = weEthIonPool;

        vm.startPrank(vault.owner());
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

        vm.startPrank(vault.owner());
        vm.expectRevert(Vault.InvalidSupplyQueueLength.selector);
        vault.updateSupplyQueue(invalidLengthQueue);

        IIonPool[] memory zeroAddressQueue = new IIonPool[](3);
        vm.expectRevert(Vault.InvalidSupplyQueuePool.selector);
        vault.updateSupplyQueue(zeroAddressQueue);

        IIonPool[] memory notSupportedQueue = new IIonPool[](3);
        notSupportedQueue[0] = rsEthIonPool;
        notSupportedQueue[1] = rswEthIonPool;
        notSupportedQueue[2] = IIonPool(address(uint160(uint256(keccak256("address not in supported markets")))));

        vm.expectRevert(Vault.InvalidSupplyQueuePool.selector);
        vault.updateSupplyQueue(notSupportedQueue);
    }

    function test_UpdateWithdrawQueue() public { }

    function test_Revert_UpdateWithdrawQUeue() public { }
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

        // error bound for resulting total assets after a withdraw
        uint256 totalAssetsRoundingError = totalAssetsREAfterWithdraw(withdrawAmount, rsEthIonPool.supplyFactor());
        uint256 maxWithdrawRoundingError = maxWithdrawREAfterWithdraw(withdrawAmount, prevTotalAssets, prevTotalSupply);

        // vault
        assertLe(vault.totalAssets(), expectedNewTotalAssets, "vault total assets");
        assertEq(
            expectedNewTotalAssets - vault.totalAssets(), totalAssetsRoundingError, "vault total assets rounding error"
        );
        assertEq(vault.totalSupply(), expectedNewTotalSupply, "vault shares total supply");

        assertEq(
            vault.totalAssets(), rsEthIonPool.getUnderlyingClaimOf(address(vault)), "single market for total assets"
        );
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "valt's base asset balance should be zero");

        // user
        assertLe(vault.maxWithdraw(address(this)), expectedMaxWithdraw, "user max withdraw");
        assertEq(
            expectedMaxWithdraw - vault.maxWithdraw(address(this)),
            maxWithdrawRoundingError,
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
        console2.log("totalAssetsRoundingError: ", totalAssetsRoundingError);
        uint256 maxWithdrawRoundingError = maxWithdrawREAfterWithdraw(withdrawAmount, prevTotalAssets, prevTotalSupply);

        // pool1 deposit 2 withdraw 2
        // pool2 deposit 3 withdraw 3
        // pool3 deposit 5 withdraw 4

        // vault
        assertLe(vault.totalAssets(), expectedNewTotalAssets, "vault total assets");
        assertEq(
            expectedNewTotalAssets - vault.totalAssets(), totalAssetsRoundingError, "vault total assets rounding error"
        );
        assertEq(vault.totalSupply(), expectedNewTotalSupply, "vault shares total supply");

        // assertEq(rsEthIonPool.getUnderlyingClaimOf(address(vault)), 0, "vault pool1 balance");
        // assertEq(rswEthIonPool.getUnderlyingClaimOf(address(vault)), 0, "vault pool2 balance");
        // assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), 1e18, "vault pool3 balance");

        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "vault base asset balance should be zero");

        // users
        // assertEq(vault.balanceOf(address(this)), depositAmount - withdrawAmount, "user vault shares balance");
        // assertEq(BASE_ASSET.balanceOf(address(this)), withdrawAmount, "user base asset balance");
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

        int256 rswEthDiff = -2e18;
        int256 weEthDiff = -1e18;
        int256 rsEthDiff = 3e18;

        // withdraw 2 from pool2
        // withdraw 1 from pool3
        // deposit 3 to pool1
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: rswEthDiff });
        allocs[1] = Vault.MarketAllocation({ pool: weEthIonPool, assets: weEthDiff });
        allocs[2] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: rsEthDiff });

        vm.prank(vault.owner());
        vault.reallocate(allocs);

        uint256 newTotalAssets = vault.totalAssets();

        // Underlying claim goes down by the difference
        // Resulting claim for the vault after withdrawing an amount
        // - currentClaim.
        // - withdrawAmount
        // resulting claim diff = ceiling(withdrawAmount / SF) * SF
        assertEq(rsEthIonPool.getUnderlyingClaimOf(address(vault)), 5e18, "rsEth vault iToken claim");
        assertEq(rswEthIonPool.getUnderlyingClaimOf(address(vault)), 1e18, "rswEth vault iToken claim");
        assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), 4e18, "weEth vault iToken claim");

        // Resulting underlying balance in the vault should exactly be the sum.
        // assertEq(BASE_ASSET.balanceOf(address(this)), rswEthDiff + weEthDiff + rsEthDiff, "base asset balance");

        assertEq(prevTotalAssets, newTotalAssets, "total assets should remain the same");
    }

    function test_Reallocate_ToSingleMarket() public {
        uint256 depositAmount = 10e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rswEthIonPool, rsEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 2e18, 3e18, 5e18);

        vault.deposit(depositAmount, address(this));

        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        uint256 prevTotalAssets = vault.totalAssets();

        // withdraw 5 from pool3
        // withdraw 2 from pool1
        // deposit 7 to pool2
        // pool1 2 -> 0
        // pool2 3 -> 10
        // pool3 5 -> 0
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: 0 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: 0 });
        allocs[2] = Vault.MarketAllocation({ pool: weEthIonPool, assets: 10e18 });

        vm.prank(vault.owner());
        vault.reallocate(allocs);

        uint256 newTotalAssets = vault.totalAssets();

        assertEq(rsEthIonPool.getUnderlyingClaimOf(address(vault)), 0, "rsEth vault iToken claim");
        assertEq(rswEthIonPool.getUnderlyingClaimOf(address(vault)), 0, "rswEth vault iToken claim");
        assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), 10e18, "weEth vault iToken claim");

        assertEq(prevTotalAssets, newTotalAssets, "total assets should remain the same");
    }

    function test_Revert_Reallocate_AllocationCapExceeded() public {
        uint256 depositAmount = 10e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rswEthIonPool, rsEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 2e18, 3e18, 5e18);

        vault.deposit(depositAmount, address(this));

        updateAllocationCaps(vault, 9e18, type(uint256).max, type(uint256).max);

        uint256 prevTotalAssets = vault.totalAssets();

        // tries to deposit 10e18 to 9e18 allocation cap
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: 0 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: 0 });
        allocs[2] = Vault.MarketAllocation({ pool: weEthIonPool, assets: 10e18 });

        vm.prank(vault.owner());
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
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: 0 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: 0 });
        allocs[2] = Vault.MarketAllocation({ pool: weEthIonPool, assets: 10e18 });

        vm.prank(vault.owner());
        vm.expectRevert(abi.encodeWithSelector(IIonPool.DepositSurpassesSupplyCap.selector, 8e18, 5e18));
        vault.reallocate(allocs);
    }

    function test_Revert_Reallocate_InvalidReallocation() public {
        uint256 depositAmount = 25e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rswEthIonPool, rsEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 10e18, 10e18, 10e18);

        vault.deposit(depositAmount, address(this));

        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        // tries to deposit less than total withdrawn
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: weEthIonPool, assets: 5e18 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, assets: 4e18 });
        allocs[2] = Vault.MarketAllocation({ pool: rswEthIonPool, assets: 6e18 });

        vm.prank(vault.owner());
        vm.expectRevert(Vault.InvalidReallocation.selector);
        vault.reallocate(allocs);
    }
}

contract Vault_WithoutRate is VaultDeposit, VaultWithdraw, VaultReallocate {
    function setUp() public override(VaultDeposit, VaultWithdraw, VaultReallocate) {
        super.setUp();
    }
}

contract VaultDeposit_WithRate is VaultDeposit, VaultWithdraw, VaultReallocate {
    function setUp() public override(VaultDeposit, VaultWithdraw, VaultReallocate) {
        super.setUp();

        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(1.12332323424e27);
        IonPoolExposed(address(rsEthIonPool)).setSupplyFactor(1.7273727372e27);
        IonPoolExposed(address(rswEthIonPool)).setSupplyFactor(1.293828382e27);
    }
}

contract VaultInteraction_WithInflatedRate is VaultDeposit, VaultWithdraw, VaultReallocate {
    function setUp() public override(VaultDeposit, VaultWithdraw, VaultReallocate) {
        super.setUp();

        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(5.12332323424e27);
        IonPoolExposed(address(rsEthIonPool)).setSupplyFactor(5.7273727372e27);
        IonPoolExposed(address(rswEthIonPool)).setSupplyFactor(5.293828382e27);
    }
}

// contract VaultInteraction_WithFee is VaultDeposit, VaultWithdraw, VaultReallocate {
//     function setUp() public override {
//         super.setUp();

//         // set fees
//         // abstract tests can be modified to calculate for fees and additional asserts with if statements
//         // also do VaultInteraction_WithRate_WithFee
//     }
// }

// contract VaultInteraction_WithYield is VaultSharedSetup { }

// contract VaultInteraction_WithRate_WithFee_WithYield { }
// WithYield warps time forward and has interest accrue during each of the test executions
