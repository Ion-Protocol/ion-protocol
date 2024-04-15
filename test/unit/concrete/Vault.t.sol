// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Vault } from "./../../../src/Vault.sol";
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
// import { StdStorage, stdStorage } from "../../../../lib/forge-safe/lib/forge-std/src/StdStorage.sol";

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

using EnumerableSet for EnumerableSet.AddressSet;

address constant VAULT_OWNER = address(1);
address constant FEE_RECIPIENT = address(2);

struct InitializeIonPool {
    address underlying;
    address treasury;
    uint8 decimals;
    string name;
    string symbol;
    address initialDefaultAdmin;
}

contract VaultSharedSetup is IonPoolSharedSetup {
    using stdStorage for StdStorage;

    StdStorage stdstore1;

    Vault vault;
    IonLens ionLens;

    IERC20 immutable BASE_ASSET = IERC20(address(new ERC20PresetMinterPauser("Lido Wrapped Staked ETH", "wstETH")));
    IERC20 immutable WEETH = IERC20(address(new ERC20PresetMinterPauser("EtherFi Restaked ETH", "weETH")));
    IERC20 immutable RSETH = IERC20(address(new ERC20PresetMinterPauser("KelpDAO Restaked ETH", "rsETH")));
    IERC20 immutable RSWETH = IERC20(address(new ERC20PresetMinterPauser("Swell Restaked ETH", "rswETH")));

    IIonPool weEthIonPool;
    IIonPool rsEthIonPool;
    IIonPool rswEthIonPool;

    function setUp() public virtual override {
        super.setUp();

        weEthIonPool = deployIonPool(BASE_ASSET, WEETH, address(this));
        rsEthIonPool = deployIonPool(BASE_ASSET, RSETH, address(this));
        rswEthIonPool = deployIonPool(BASE_ASSET, RSWETH, address(this));

        ionLens = new IonLens();

        vault = new Vault(VAULT_OWNER, FEE_RECIPIENT, BASE_ASSET, ionLens, "Ion Vault Token", "IVT");
        vm.startPrank(vault.owner());
        IIonPool[] memory markets = new IIonPool[](3);
        markets[0] = weEthIonPool;
        markets[1] = rsEthIonPool;
        markets[2] = rswEthIonPool;

        vault.addSupportedMarkets(markets);
        vm.stopPrank();
    }

    function setERC20Balance(address token, address usr, uint256 amt) public {
        stdstore1.target(token).sig(IERC20(token).balanceOf.selector).with_key(usr).checked_write(amt);
        require(IERC20(token).balanceOf(usr) == amt, "balance not set");
    }

    // deploys a single IonPool with default configs
    function deployIonPool(
        IERC20 underlying,
        IERC20 collateral,
        address initialDefaultAdmin
    )
        internal
        returns (IIonPool ionPool)
    {
        IYieldOracle yieldOracle = _getYieldOracle();
        interestRateModule = new InterestRate(ilkConfigs, yieldOracle);

        Whitelist whitelist = _getWhitelist();

        bytes memory initializeBytes = abi.encodeWithSelector(
            IonPool.initialize.selector,
            underlying,
            address(this),
            DECIMALS,
            NAME,
            SYMBOL,
            initialDefaultAdmin,
            interestRateModule,
            whitelist
        );

        IonPoolExposed ionPoolImpl = new IonPoolExposed();
        ProxyAdmin ionProxyAdmin = new ProxyAdmin(address(this));

        IonPoolExposed ionPoolProxy = IonPoolExposed(
            address(new TransparentUpgradeableProxy(address(ionPoolImpl), address(ionProxyAdmin), initializeBytes))
        );

        ionPool = IIonPool(address(ionPoolProxy));

        ionPool.grantRole(ionPool.ION(), address(this));
        ionPool.grantRole(ionPool.PAUSE_ROLE(), address(this));
        ionPool.updateSupplyCap(type(uint256).max);

        ionPool.initializeIlk(address(collateral));
        ionPool.updateIlkSpot(0, address(_getSpotOracle()));
        ionPool.updateIlkDebtCeiling(0, _getDebtCeiling(0));

        GemJoin gemJoin = new GemJoin(IonPool(address(ionPool)), collateral, 0, address(this));
        ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(gemJoin));
    }
}

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

contract VaultInteraction_WithoutRate is VaultSharedSetup {
    IIonPool[] pools;

    function setUp() public override {
        super.setUp();
        BASE_ASSET.approve(address(vault), type(uint256).max);

        pools = new IIonPool[](3);
        pools[0] = weEthIonPool;
        pools[1] = rsEthIonPool;
        pools[2] = rswEthIonPool;
    }

    // In the order of supply queue
    function updateSupplyCaps(Vault _vault, uint256 cap1, uint256 cap2, uint256 cap3) public {
        _vault.supplyQueue(0).updateSupplyCap(cap1);
        _vault.supplyQueue(1).updateSupplyCap(cap2);
        _vault.supplyQueue(2).updateSupplyCap(cap3);
    }

    // In the order of supply queue
    function updateAllocationCaps(Vault _vault, uint256 cap1, uint256 cap2, uint256 cap3) public {
        uint256[] memory caps = new uint256[](3);
        caps[0] = cap1;
        caps[1] = cap2;
        caps[2] = cap3;

        IIonPool[] memory queue = new IIonPool[](3);
        queue[0] = _vault.supplyQueue(0);
        queue[1] = _vault.supplyQueue(1);
        queue[2] = _vault.supplyQueue(2);

        vm.prank(_vault.owner());
        _vault.updateAllocationCaps(queue, caps);
    }

    function updateSupplyQueue(Vault _vault, IIonPool pool1, IIonPool pool2, IIonPool pool3) public {
        IIonPool[] memory supplyQueue = new IIonPool[](3);
        supplyQueue[0] = pool1;
        supplyQueue[1] = pool2;
        supplyQueue[2] = pool3;
        vm.prank(_vault.owner());
        _vault.updateSupplyQueue(supplyQueue);
    }

    function updateWithdrawQueue(Vault _vault, IIonPool pool1, IIonPool pool2, IIonPool pool3) public {
        IIonPool[] memory queue = new IIonPool[](3);
        queue[0] = pool1;
        queue[1] = pool2;
        queue[2] = pool3;
        vm.prank(_vault.owner());
        _vault.updateWithdrawQueue(queue);
    }

    function test_Deposit_WithoutSupplyCap_WithoutAllocationCap() public {
        uint256 depositAmount = 1e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rsEthIonPool, rswEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");
        assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), depositAmount, "vault iToken claim");
    }

    function test_Deposit_WithoutSupplyCap_WithAllocationCap_EqualDeposits() public {
        uint256 depositAmount = 3e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rsEthIonPool, rswEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 1e18, 1e18, 1e18);

        // 3e18 gets spread out equally amongst the three pools
        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), 1e18, "weEth vault iToken claim");
        assertEq(rsEthIonPool.getUnderlyingClaimOf(address(vault)), 1e18, "rsEth vault iToken claim");
        assertEq(rswEthIonPool.getUnderlyingClaimOf(address(vault)), 1e18, "rswEth vault iToken claim");
    }

    function test_Deposit_WithoutSupplyCap_WithAllocationCap_DifferentDeposits() public {
        uint256 depositAmount = 10e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, 3e18, 5e18, 7e18);

        // 3e18 gets spread out equally amongst the three pools
        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        assertEq(rsEthIonPool.getUnderlyingClaimOf(address(vault)), 3e18, "rsEth vault iToken claim");
        assertEq(rswEthIonPool.getUnderlyingClaimOf(address(vault)), 5e18, "rswEth vault iToken claim");
        assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), 2e18, "weEth vault iToken claim");
    }

    function test_Deposit_SupplyCap_Below_AllocationCap_DifferentDeposits() public {
        uint256 depositAmount = 12e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);
        updateSupplyCaps(vault, 3e18, 10e18, 5e18);
        updateAllocationCaps(vault, 5e18, 7e18, 20e18);

        vault.deposit(depositAmount, address(this));

        assertEq(vault.totalSupply(), depositAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), depositAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        // pool1 3e18, pool2 7e18, pool3 2e18
        assertEq(rsEthIonPool.getUnderlyingClaimOf(address(vault)), 3e18, "rsEth vault iToken claim");
        assertEq(rswEthIonPool.getUnderlyingClaimOf(address(vault)), 7e18, "rswEth vault iToken claim");
        assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), 2e18, "weEth vault iToken claim");
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

    function test_Withdraw_SingleMarket() public {
        uint256 depositAmount = 10e18;
        uint256 withdrawAmount = 5e18;

        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        updateWithdrawQueue(vault, rsEthIonPool, rswEthIonPool, weEthIonPool);

        vault.deposit(depositAmount, address(this));

        vault.withdraw(withdrawAmount, address(this), address(this));

        assertEq(vault.totalSupply(), depositAmount - withdrawAmount, "vault shares total supply");
        assertEq(vault.balanceOf(address(this)), withdrawAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "base asset balance should be zero");

        assertEq(rsEthIonPool.balanceOf(address(vault)), depositAmount - withdrawAmount, "vault pool balance");
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

        vault.withdraw(withdrawAmount, address(this), address(this));

        // pool1 deposit 2 withdraw 2
        // pool2 deposit 3 withdraw 3
        // pool3 deposit 5 withdraw 4

        // vault
        assertEq(vault.totalSupply(), depositAmount - withdrawAmount, "vault shares total supply");
        assertEq(BASE_ASSET.balanceOf(address(vault)), 0, "vault base asset balance should be zero");
        assertEq(rsEthIonPool.balanceOf(address(vault)), 0, "vault pool1 balance");
        assertEq(rswEthIonPool.balanceOf(address(vault)), 0, "vault pool2 balance");
        assertEq(weEthIonPool.balanceOf(address(vault)), 1e18, "vault pool3 balance");

        // users
        assertEq(vault.balanceOf(address(this)), depositAmount - withdrawAmount, "user vault shares balance");
        assertEq(BASE_ASSET.balanceOf(address(this)), withdrawAmount, "user base asset balance");
    }

    function test_Withdraw_FullWithdraw() public { }

    function test_Withdraw_Different_Queue_Order() public { }

    function test_DepositAndWithdraw_MultipleUsers() public { }

    function test_Revert_Withdraw() public { }

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

        // withdraw 2 from pool2
        // withdraw 1 from pool3
        // deposit 3 to pool1
        // pool1 2 -> 5
        // pool2 3 -> 1
        // pool3 5 -> 4
        Vault.MarketAllocation[] memory allocs = new Vault.MarketAllocation[](3);
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, targetAssets: 1e18 });
        allocs[1] = Vault.MarketAllocation({ pool: weEthIonPool, targetAssets: 4e18 });
        allocs[2] = Vault.MarketAllocation({ pool: rsEthIonPool, targetAssets: 5e18 });

        vm.prank(vault.owner());
        vault.reallocate(allocs);

        uint256 newTotalAssets = vault.totalAssets();

        assertEq(rsEthIonPool.getUnderlyingClaimOf(address(vault)), 5e18, "rsEth vault iToken claim");
        assertEq(rswEthIonPool.getUnderlyingClaimOf(address(vault)), 1e18, "rswEth vault iToken claim");
        assertEq(weEthIonPool.getUnderlyingClaimOf(address(vault)), 4e18, "weEth vault iToken claim");

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
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, targetAssets: 0 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, targetAssets: 0 });
        allocs[2] = Vault.MarketAllocation({ pool: weEthIonPool, targetAssets: 10e18 });

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
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, targetAssets: 0 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, targetAssets: 0 });
        allocs[2] = Vault.MarketAllocation({ pool: weEthIonPool, targetAssets: 10e18 });

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
        allocs[0] = Vault.MarketAllocation({ pool: rswEthIonPool, targetAssets: 0 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, targetAssets: 0 });
        allocs[2] = Vault.MarketAllocation({ pool: weEthIonPool, targetAssets: 10e18 });

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
        allocs[0] = Vault.MarketAllocation({ pool: weEthIonPool, targetAssets: 5e18 });
        allocs[1] = Vault.MarketAllocation({ pool: rsEthIonPool, targetAssets: 4e18 });
        allocs[2] = Vault.MarketAllocation({ pool: rswEthIonPool, targetAssets: 6e18 });

        vm.prank(vault.owner());
        vm.expectRevert(Vault.InvalidReallocation.selector);
        vault.reallocate(allocs);
    }
}

contract VaultInteraction_WithRate is VaultSharedSetup {
    function setUp() public override {
        super.setUp();
    }
}

contract VaultInteraction_WithYield is VaultShapredSetup { }
