// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Vault } from "./../../../../src/Vault.sol";
import { IonPool } from "./../../../../src/IonPool.sol";
import { WSTETH_ADDRESS } from "./../../../../src/Constants.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
// import { StdStorage, stdStorage } from "../../../../lib/forge-safe/lib/forge-std/src/StdStorage.sol";

import "forge-std/Test.sol";

using EnumerableSet for EnumerableSet.AddressSet;

IonPool constant WEETH_IONPOOL = IonPool(0x0000000000eaEbd95dAfcA37A39fd09745739b78);
IonPool constant RSETH_IONPOOL = IonPool(0x0000000000E33e35EE6052fae87bfcFac61b1da9);
IonPool constant RSWETH_IONPOOL = IonPool(0x00000000007C8105548f9d0eE081987378a6bE93);

address constant VAULT_OWNER = address(1);
address constant FEE_RECIPIENT = address(2);
IERC20 constant BASE_ASSET = WSTETH_ADDRESS;

contract VaultForkBase is Test {
    using stdStorage for StdStorage;

    StdStorage stdstore1;
    Vault vault;
    uint256 internal forkBlock = 0;

    function setERC20Balance(address token, address usr, uint256 amt) public {
        stdstore1.target(token).sig(IERC20(token).balanceOf.selector).with_key(usr).checked_write(amt);
        require(IERC20(token).balanceOf(usr) == amt, "balance not set");
    }

    function updateSupplyCap(IonPool pool, uint256 cap) internal {
        vm.startPrank(pool.owner());
        pool.updateSupplyCap(cap);
        vm.stopPrank();
    }

    function setUp() public virtual {
        if (forkBlock == 0) vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"));
        else vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"), forkBlock);

        vault = new Vault(VAULT_OWNER, FEE_RECIPIENT, BASE_ASSET, "Ion Vault Token", "IVT");

        IonPool[] memory markets = new IonPool[](3);
        markets[0] = WEETH_IONPOOL;
        markets[1] = RSETH_IONPOOL;
        markets[2] = RSWETH_IONPOOL;

        vm.startPrank(vault.owner());

        vault.addSupportedMarkets(markets);
        vault.updateSupplyQueue(markets);
        vault.updateWithdrawQueue(markets);

        vm.stopPrank();

        BASE_ASSET.approve(address(vault), type(uint256).max);
    }
}

contract VaultUnitTest is Test {
    Vault vault;

    function setUp() public {
        vault = new Vault(VAULT_OWNER, FEE_RECIPIENT, BASE_ASSET, "Ion Vault Token", "IVT");

        vm.startPrank(vault.owner());
        IonPool[] memory markets = new IonPool[](3);
        markets[0] = WEETH_IONPOOL;
        markets[1] = RSETH_IONPOOL;
        markets[2] = RSWETH_IONPOOL;

        vault.addSupportedMarkets(markets);
        vm.stopPrank();
    }

    function test_AddSupportedMarketsSeparately() public {
        Vault _vault = new Vault(VAULT_OWNER, FEE_RECIPIENT, BASE_ASSET, "Ion Vault Token", "IVT");
        vm.startPrank(_vault.owner());

        IonPool[] memory market1 = new IonPool[](1);
        market1[0] = WEETH_IONPOOL;
        IonPool[] memory market2 = new IonPool[](1);
        market2[0] = RSETH_IONPOOL;
        IonPool[] memory market3 = new IonPool[](1);
        market3[0] = RSWETH_IONPOOL;

        vault.addSupportedMarkets(market1);
        address[] memory supportedMarkets1 = _vault.getSupportedMarkets();
        assertEq(supportedMarkets1.length, 1, "supported markets length one");
        assertEq(supportedMarkets1[0], address(WEETH_IONPOOL), "first supported markets address");

        vault.addSupportedMarkets(market2);
        address[] memory supportedMarkets2 = _vault.getSupportedMarkets();
        assertEq(supportedMarkets2.length, 2, "supported markets length two");
        assertEq(supportedMarkets2[1], address(RSETH_IONPOOL), "second supported markets address");

        vault.addSupportedMarkets(market3);
        address[] memory supportedMarkets3 = _vault.getSupportedMarkets();
        assertEq(supportedMarkets3.length, 3, "supported markets length three");
        assertEq(supportedMarkets3[2], address(RSWETH_IONPOOL), "third supported markets address");
    }

    function test_AddSupportedMarketsTogether() public {
        Vault _vault = new Vault(VAULT_OWNER, FEE_RECIPIENT, BASE_ASSET, "Ion Vault Token", "IVT");
        vm.startPrank(_vault.owner());
        IonPool[] memory markets = new IonPool[](3);
        markets[0] = WEETH_IONPOOL;
        markets[1] = RSETH_IONPOOL;
        markets[2] = RSWETH_IONPOOL;

        vault.addSupportedMarkets(markets);
        address[] memory supportedMarkets = _vault.getSupportedMarkets();

        assertEq(supportedMarkets.length, 3, "supported markets length");
        assertEq(supportedMarkets[0], address(WEETH_IONPOOL), "first supported markets address");
        assertEq(supportedMarkets[1], address(RSETH_IONPOOL), "second supported markets address");
        assertEq(supportedMarkets[2], address(RSWETH_IONPOOL), "third supported markets address");
    }

    function test_UpdateSupplyQueue() public {
        IonPool[] memory supplyQueue = new IonPool[](3);
        supplyQueue[0] = RSETH_IONPOOL;
        supplyQueue[1] = RSWETH_IONPOOL;
        supplyQueue[2] = WEETH_IONPOOL;

        vm.startPrank(vault.owner());
        vault.updateSupplyQueue(supplyQueue);

        assertEq(address(vault.supplyQueue(0)), address(supplyQueue[0]), "updated supply queue");
        assertEq(address(vault.supplyQueue(1)), address(supplyQueue[1]), "updated supply queue");
        assertEq(address(vault.supplyQueue(2)), address(supplyQueue[2]), "updated supply queue");
    }

    function test_Revert_UpdateSupplyQueue() public {
        IonPool[] memory invalidLengthQueue = new IonPool[](5);
        for (uint8 i = 0; i < 5; i++) {
            invalidLengthQueue[i] = WEETH_IONPOOL;
        }

        vm.startPrank(vault.owner());
        vm.expectRevert(Vault.InvalidSupplyQueueLength.selector);
        vault.updateSupplyQueue(invalidLengthQueue);

        IonPool[] memory zeroAddressQueue = new IonPool[](3);
        vm.expectRevert(Vault.InvalidSupplyQueuePool.selector);
        vault.updateSupplyQueue(zeroAddressQueue);

        IonPool[] memory notSupportedQueue = new IonPool[](3);
        notSupportedQueue[0] = RSETH_IONPOOL;
        notSupportedQueue[1] = RSWETH_IONPOOL;
        notSupportedQueue[2] = IonPool(address(uint160(uint256(keccak256("address not in supported markets")))));

        vm.expectRevert(Vault.InvalidSupplyQueuePool.selector);
        vault.updateSupplyQueue(notSupportedQueue);
    }

    function test_UpdateWithdrawQueue() public { }

    function test_Revert_UpdateWithdrawQUeue() public { }
}

/**
 * Vault state that needs to be checked
 * - Vault's shares total supply
 * - Vault's total iToken balance
 * - User's vault shares balance
 */
contract Vault_ForkTest is VaultForkBase {
    function test_GetSupplyCap() public {
        vault.getPoolSupplyCap(WEETH_IONPOOL);
    }

    /**
     * Because the first market's allocation cap and supply cap is high enough,
     * all deposits go into the first market.
     */
    function test_DepositFirstMarketOnly() public {
        setERC20Balance(address(BASE_ASSET), address(this), 100e18);
        console2.log("BASE_ASSET.balanceOf(address(this)): ", BASE_ASSET.balanceOf(address(this)));

        IonPool pool1 = vault.supplyQueue(0);
        IonPool pool2 = vault.supplyQueue(1);
        IonPool pool3 = vault.supplyQueue(2);

        updateSupplyCap(pool1, type(uint256).max);

        vault.deposit(100e18, address(this));

        // vault shares
        // vault iToken balance
    }

    function test_Withdraw() public { }
}

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
