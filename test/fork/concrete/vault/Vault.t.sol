// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Vault } from "./../../../../src/vault/Vault.sol";
import { IonPool } from "./../../../../src/IonPool.sol";
import { Whitelist } from "./../../../../src/Whitelist.sol";
import { IIonPool } from "./../../../../src/interfaces/IIonPool.sol";
import { IonLens } from "./../../../../src/periphery/IonLens.sol";
import { WSTETH_ADDRESS } from "./../../../../src/Constants.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
// import { StdStorage, stdStorage } from "../../../../lib/forge-safe/lib/forge-std/src/StdStorage.sol";

import "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

using EnumerableSet for EnumerableSet.AddressSet;

IIonPool constant WEETH_IONPOOL = IIonPool(0x0000000000eaEbd95dAfcA37A39fd09745739b78);
IIonPool constant RSETH_IONPOOL = IIonPool(0x0000000000E33e35EE6052fae87bfcFac61b1da9);
IIonPool constant RSWETH_IONPOOL = IIonPool(0x00000000007C8105548f9d0eE081987378a6bE93);
Whitelist constant WHITELIST = Whitelist(0x7E317f99aA313669AaCDd8dB3927ff3aCB562dAD);
bytes32 constant ION_ROLE = 0x5ab1a5ffb29c47d95dec8c5f9ad49a551754822b51a3359ed1c21e2be24beefa;

address constant VAULT_OWNER = address(1);
address constant FEE_RECIPIENT = address(2);
IERC20 constant BASE_ASSET = WSTETH_ADDRESS;

contract VaultForkBase is Test {
    using stdStorage for StdStorage;

    StdStorage stdstore1;
    IonLens public ionLens;
    Vault vault;

    uint256 internal forkBlock = 0;
    address internal poolAdmin;

    IIonPool[] markets;

    function setERC20Balance(address token, address usr, uint256 amt) public {
        stdstore1.target(token).sig(IERC20(token).balanceOf.selector).with_key(usr).checked_write(amt);
        require(IERC20(token).balanceOf(usr) == amt, "balance not set");
    }

    function updateSupplyCap(IIonPool pool, uint256 cap) internal {
        vm.startPrank(poolAdmin);
        pool.updateSupplyCap(cap);
        vm.stopPrank();
        assertEq(ionLens.wethSupplyCap(pool), cap, "supply cap update");
    }

    function _updateImpl(IIonPool proxy, IIonPool impl) internal {
        vm.store(
            address(proxy),
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
            bytes32(uint256(uint160(address(impl))))
        );
    }

    function setUp() public virtual {
        if (forkBlock == 0) vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"));
        else vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"), forkBlock);

        poolAdmin = WEETH_IONPOOL.defaultAdmin();
        // update fork contract to the latest implementation with
        // transferradbility + non-rebasing + removed getters
        ionLens = new IonLens();

        IonPool updatedImpl = new IonPool();

        _updateImpl(WEETH_IONPOOL, IIonPool(address(updatedImpl)));
        _updateImpl(RSETH_IONPOOL, IIonPool(address(updatedImpl)));
        _updateImpl(RSWETH_IONPOOL, IIonPool(address(updatedImpl)));

        vault = new Vault(VAULT_OWNER, FEE_RECIPIENT, BASE_ASSET, ionLens, "Ion Vault Token", "IVT");

        markets = new IIonPool[](3);
        markets[0] = WEETH_IONPOOL;
        markets[1] = RSETH_IONPOOL;
        markets[2] = RSWETH_IONPOOL;

        vm.startPrank(vault.owner());

        vault.addSupportedMarkets(markets);
        vault.updateSupplyQueue(markets);
        vault.updateWithdrawQueue(markets);

        vm.stopPrank();

        BASE_ASSET.approve(address(vault), type(uint256).max);

        vm.prank(poolAdmin);
        WHITELIST.updateLendersRoot(bytes32(0));
    }
}

/**
 * Vault state that needs to be checked
 * - Vault's shares total supply
 * - Vault's total iToken balance
 * - User's vault shares balance
 */
contract Vault_ForkTest is VaultForkBase {
    function setUp() public override {
        super.setUp();

        uint256[] memory newCaps = new uint256[](3);
        newCaps[0] = 100e18;
        newCaps[1] = 100e18;
        newCaps[2] = 100e18;
        vm.prank(vault.owner());
        vault.updateAllocationCaps(markets, newCaps);
    }

    /**
     * Because the first market's allocation cap and supply cap is high enough,
     * all deposits go into the first market.
     */
    function test_DepositFirstMarketOnly() public {
        setERC20Balance(address(BASE_ASSET), address(this), 100e18);
        console2.log("BASE_ASSET.balanceOf(address(this)): ", BASE_ASSET.balanceOf(address(this)));

        IIonPool pool1 = vault.supplyQueue(0);
        IIonPool pool2 = vault.supplyQueue(1);
        IIonPool pool3 = vault.supplyQueue(2);

        console2.log("pool1: ", address(pool1));
        updateSupplyCap(pool1, type(uint256).max);

        vault.deposit(100e18, address(this));

        // vault shares
        // vault iToken balance
    }

    function test_Withdraw() public { }
}

contract Vault_ForkTest_WithRateAccrual is VaultForkBase { }

contract Vault_ForkFuzzTest is VaultForkBase {
    function setUp() public override {
        super.setUp();
    }

    /**
     * Start each pool at a random total supply amount and a supply cap.
     * The total supply amount must be less than or equal to the supply cap.
     * Deposit random amount of assets into the vault.
     * The deposit amount must be equal to the change in deposits across all lending pools.
     * It should only revert if the total available supply amount is less than the deposit amount.
     */
    function testForkFuzz_DepositAllMarkets(uint256 assets) public { }

    function testFuzz_Withdraw(uint256 assets) public { }

    /**
     * The totalAssets should return the total rebased claim across all markets at a given time.
     */
    function testFuzz_totalAssets() public { }

    /**
     * The total amount of fees collected at a random time in the futuer should be split
     * between the vault depositors and the fee recipient.
     */
    function testFuzz_Fees() public { }
}
