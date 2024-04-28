// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WadRayMath, RAY } from "./../../src/libraries/math/WadRayMath.sol";
import { Vault } from "./../../src/vault/Vault.sol";
import { IonPool } from "./../../src/IonPool.sol";
import { IIonPool } from "./../../src/interfaces/IIonPool.sol";
import { IonLens } from "./../../src/periphery/IonLens.sol";
import { GemJoin } from "./../../src/join/GemJoin.sol";
import { YieldOracle } from "./../../src/YieldOracle.sol";
import { IYieldOracle } from "./../../src/interfaces/IYieldOracle.sol";
import { InterestRate } from "./../../src/InterestRate.sol";
import { Whitelist } from "./../../src/Whitelist.sol";
import { ProxyAdmin } from "./../../src/admin/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "./../../src/admin/TransparentUpgradeableProxy.sol";
import { ERC20PresetMinterPauser } from "./ERC20PresetMinterPauser.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { IonPoolSharedSetup, IonPoolExposed } from "./IonPoolSharedSetup.sol";

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

using EnumerableSet for EnumerableSet.AddressSet;
using WadRayMath for uint256;
using Math for uint256;

contract VaultSharedSetup is IonPoolSharedSetup {
    using stdStorage for StdStorage;

    StdStorage stdstore1;

    Vault vault;
    IonLens ionLens;

    // roles
    address constant VAULT_ADMIN = address(uint160(uint256(keccak256("VAULT_ADMIN"))));
    address constant OWNER = address(uint160(uint256(keccak256("OWNER"))));
    address constant ALLOCATOR = address(uint160(uint256(keccak256("ALLOCATOR"))));

    uint48 constant INITIAL_DELAY = 0;
    address constant FEE_RECIPIENT = address(uint160(uint256(keccak256("FEE_RECIPIENT"))));
    uint256 constant ZERO_FEES = 0;

    IERC20 immutable BASE_ASSET = IERC20(address(new ERC20PresetMinterPauser("Lido Wrapped Staked ETH", "wstETH")));
    IERC20 immutable WEETH = IERC20(address(new ERC20PresetMinterPauser("EtherFi Restaked ETH", "weETH")));
    IERC20 immutable RSETH = IERC20(address(new ERC20PresetMinterPauser("KelpDAO Restaked ETH", "rsETH")));
    IERC20 immutable RSWETH = IERC20(address(new ERC20PresetMinterPauser("Swell Restaked ETH", "rswETH")));

    IIonPool constant IDLE = IIonPool(address(uint160(uint256(keccak256("IDLE_ASSET_HOLDINGS")))));
    IIonPool weEthIonPool;
    IIonPool rsEthIonPool;
    IIonPool rswEthIonPool;

    GemJoin weEthGemJoin;
    GemJoin rsEthGemJoin;
    GemJoin rswEthGemJoin;

    IIonPool[] markets;

    uint256[] ZERO_ALLO_CAPS = new uint256[](3);

    function setUp() public virtual override {
        super.setUp();

        weEthIonPool = deployIonPool(BASE_ASSET, WEETH, address(this));
        rsEthIonPool = deployIonPool(BASE_ASSET, RSETH, address(this));
        rswEthIonPool = deployIonPool(BASE_ASSET, RSWETH, address(this));

        ionLens = new IonLens();

        vault = new Vault(
            ionLens, BASE_ASSET, FEE_RECIPIENT, ZERO_FEES, "Ion Vault Token", "IVT", INITIAL_DELAY, VAULT_ADMIN
        );

        vm.startPrank(vault.defaultAdmin());

        vault.grantRole(vault.OWNER_ROLE(), OWNER);
        vault.grantRole(vault.ALLOCATOR_ROLE(), OWNER); // OWNER also needs to be ALLOCATOR in order to update queues
            // inside `addSupportedMarkets`.
        vault.grantRole(vault.ALLOCATOR_ROLE(), ALLOCATOR);

        markets = new IIonPool[](3);
        markets[0] = weEthIonPool;
        markets[1] = rsEthIonPool;
        markets[2] = rswEthIonPool;

        vm.stopPrank();

        vm.prank(OWNER);
        vault.addSupportedMarkets(markets, ZERO_ALLO_CAPS, markets, markets);

        BASE_ASSET.approve(address(vault), type(uint256).max);

        // pools = new IIonPool[](3);
        // pools[0] = weEthIonPool;
        // pools[1] = rsEthIonPool;
        // pools[2] = rswEthIonPool;

        weEthGemJoin =
            new GemJoin(IonPool(address(weEthIonPool)), IERC20(weEthIonPool.getIlkAddress(0)), 0, address(this));
        rsEthGemJoin =
            new GemJoin(IonPool(address(rsEthIonPool)), IERC20(rsEthIonPool.getIlkAddress(0)), 0, address(this));
        rswEthGemJoin =
            new GemJoin(IonPool(address(rswEthIonPool)), IERC20(rswEthIonPool.getIlkAddress(0)), 0, address(this));

        weEthIonPool.grantRole(weEthIonPool.GEM_JOIN_ROLE(), address(weEthGemJoin));
        rsEthIonPool.grantRole(rsEthIonPool.GEM_JOIN_ROLE(), address(rsEthGemJoin));
        rswEthIonPool.grantRole(rswEthIonPool.GEM_JOIN_ROLE(), address(rswEthGemJoin));
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

    function claimAfterDeposit(uint256 currShares, uint256 amount, uint256 supplyFactor) internal returns (uint256) {
        uint256 sharesMinted = amount.rayDivDown(supplyFactor);
        uint256 resultingShares = currShares + sharesMinted;
        return resultingShares.rayMulDown(supplyFactor);
    }

    function claimAfterWithdraw(uint256 currShares, uint256 amount, uint256 supplyFactor) internal returns (uint256) {
        uint256 sharesBurned = amount.rayDivUp(supplyFactor);
        uint256 resultingShares = currShares - sharesBurned;
        return resultingShares.rayMulDown(supplyFactor);
    }

    // --- Privileged Helper Functions ---

    // Updates in the order of supply queue
    function updateSupplyCaps(Vault _vault, uint256 cap1, uint256 cap2, uint256 cap3) internal {
        _vault.supplyQueue(0).updateSupplyCap(cap1);
        _vault.supplyQueue(1).updateSupplyCap(cap2);
        _vault.supplyQueue(2).updateSupplyCap(cap3);
    }

    // Updates in the order of the supplyQueue array
    function updateAllocationCaps(Vault _vault, uint256 cap1, uint256 cap2, uint256 cap3) internal {
        uint256[] memory caps = new uint256[](3);
        caps[0] = cap1;
        caps[1] = cap2;
        caps[2] = cap3;

        IIonPool[] memory ionPools = new IIonPool[](3);
        ionPools[0] = _vault.supplyQueue(0);
        ionPools[1] = _vault.supplyQueue(1);
        ionPools[2] = _vault.supplyQueue(2);

        vm.prank(OWNER);
        _vault.updateAllocationCaps(ionPools, caps);
    }

    function updateSupplyQueue(Vault _vault, IIonPool pool1, IIonPool pool2, IIonPool pool3) internal {
        IIonPool[] memory supplyQueue = new IIonPool[](3);
        supplyQueue[0] = pool1;
        supplyQueue[1] = pool2;
        supplyQueue[2] = pool3;
        vm.prank(ALLOCATOR);
        _vault.updateSupplyQueue(supplyQueue);
    }

    function updateWithdrawQueue(Vault _vault, IIonPool pool1, IIonPool pool2, IIonPool pool3) internal {
        IIonPool[] memory queue = new IIonPool[](3);
        queue[0] = pool1;
        queue[1] = pool2;
        queue[2] = pool3;
        vm.prank(ALLOCATOR);
        _vault.updateWithdrawQueue(queue);
    }

    // -- Queries ---

    // function expectedSupplyAmounts(Vault _vault, uint256 assets) internal returns (uint256[]) {

    // }

    // -- Exact Rounding Error Equations ---

    function postDepositClaimRE(uint256 depositAmount, uint256 supplyFactor) internal returns (uint256) {
        return (supplyFactor + 2) / RAY + 1;
    }

    // The difference between the expected total assets after withdrawal and the
    // actual total assets after withdrawal.
    // expected = prev total assets - withdraw amount
    // actual = resulting total assets on contract
    // rounding error = expected - actual
    // This equation is max bounded to supplyFactor / RAY.
    function totalAssetsREAfterWithdraw(uint256 withdrawAmount, uint256 supplyFactor) internal returns (uint256) {
        return (supplyFactor - withdrawAmount * RAY % supplyFactor) / RAY;
    }

    // Resulting vault shares?
    // The difference between the expected max withdraw after withdrawal and the
    // actual max withdraw after withdrawal.
    // TODO: totalSupply needs to change when _decimalsOffset is added
    function maxWithdrawREAfterWithdraw(
        uint256 withdrawAmount,
        uint256 totalAssets,
        uint256 totalSupply
    )
        internal
        returns (uint256)
    {
        totalAssets += 1;
        return (totalAssets - withdrawAmount * totalSupply % totalAssets) / totalSupply;
    }

    // --- IonPool Interactions ---

    function borrow(address borrower, IIonPool pool, GemJoin gemJoin, uint256 depositAmt, uint256 borrowAmt) internal {
        IERC20 collateralAsset = IERC20(address(pool.getIlkAddress(0)));

        setERC20Balance(address(collateralAsset), borrower, depositAmt);

        vm.startPrank(borrower);
        collateralAsset.approve(address(gemJoin), depositAmt);
        gemJoin.join(borrower, depositAmt);
        // move collateral to vault
        pool.depositCollateral(0, borrower, borrower, depositAmt, emptyProof);
        pool.borrow(0, borrower, borrower, borrowAmt, emptyProof);
        vm.stopPrank();
    }

    function supply(address lender, IIonPool pool, uint256 supplyAmt) internal {
        IERC20 underlying = IERC20(pool.underlying());

        setERC20Balance(address(underlying), lender, supplyAmt);

        vm.startPrank(lender);
        underlying.approve(address(pool), type(uint256).max);
        pool.supply(lender, supplyAmt, emptyProof);
        vm.stopPrank();
    }

    function newAddress(bytes memory str) internal returns (address) {
        return address(uint160(uint256(keccak256(str))));
    }
}
