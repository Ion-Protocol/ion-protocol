// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { Vault } from "./../../../../src/vault/Vault.sol";
import { VaultFactory } from "./../../../../src/vault/VaultFactory.sol";
import { VaultSharedSetup } from "../../../helpers/VaultSharedSetup.sol";
import { ERC20PresetMinterPauser } from "../../../helpers/ERC20PresetMinterPauser.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IIonPool } from "./../../../../src/interfaces/IIonPool.sol";

import { console2 } from "forge-std/console2.sol";

contract VaultFactoryTest is VaultSharedSetup {
    VaultFactory factory;

    address internal feeRecipient = address(2);
    uint256 internal feePercentage = 0.02e27;
    IERC20 internal baseAsset = BASE_ASSET;
    string internal name = "Vault Token";
    string internal symbol = "VT";

    IIonPool[] internal marketsToAdd;
    uint256[] internal allocationCaps;
    IIonPool[] internal newSupplyQueue;
    IIonPool[] internal newWithdrawQueue;

    function setUp() public override {
        super.setUp();

        factory = new VaultFactory();

        marketsToAdd.push(weEthIonPool);
        marketsToAdd.push(rsEthIonPool);
        marketsToAdd.push(rswEthIonPool);

        allocationCaps.push(1e18);
        allocationCaps.push(2e18);
        allocationCaps.push(3e18);

        newSupplyQueue.push(weEthIonPool);
        newSupplyQueue.push(rswEthIonPool);
        newSupplyQueue.push(rsEthIonPool);

        newWithdrawQueue.push(rswEthIonPool);
        newWithdrawQueue.push(rsEthIonPool);
        newWithdrawQueue.push(weEthIonPool);

        marketsArgs.marketsToAdd = marketsToAdd;
        marketsArgs.allocationCaps = allocationCaps;
        marketsArgs.newSupplyQueue = newSupplyQueue;
        marketsArgs.newWithdrawQueue = newWithdrawQueue;

        setERC20Balance(address(BASE_ASSET), address(this), MIN_INITIAL_DEPOSIT);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);
    }

    function test_CreateVault_Basic() public {
        bytes32 salt = _getSalt(address(this), "random salt");

        Vault vault = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );

        address[] memory supportedMarkets = vault.getSupportedMarkets();

        IIonPool firstInSupplyQueue = vault.supplyQueue(0);
        IIonPool secondInSupplyQueue = vault.supplyQueue(1);
        IIonPool thirdInSupplyQueue = vault.supplyQueue(2);

        IIonPool firstInWithdrawQueue = vault.withdrawQueue(0);
        IIonPool secondInWithdrawQueue = vault.withdrawQueue(1);
        IIonPool thirdInWithdrawQueue = vault.withdrawQueue(2);

        assertEq(vault.defaultAdmin(), VAULT_ADMIN, "default admin");
        assertEq(vault.feeRecipient(), feeRecipient, "fee recipient");
        assertEq(vault.feePercentage(), feePercentage, "fee percentage");
        assertEq(address(vault.BASE_ASSET()), address(baseAsset), "base asset");

        assertEq(supportedMarkets.length, 3, "supported markets length");

        for (uint256 i = 0; i != supportedMarkets.length; ++i) {
            assertEq(address(supportedMarkets[i]), address(marketsToAdd[i]), "supported markets");
            assertEq(address(vault.supplyQueue(i)), address(newSupplyQueue[i]), "supply queue");
            assertEq(address(vault.withdrawQueue(i)), address(newWithdrawQueue[i]), "withdraw queue");
        }

        // initial deposits
        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "initial deposit spent");
        assertEq(vault.totalAssets(), MIN_INITIAL_DEPOSIT, "total assets");
        assertEq(vault.totalSupply(), MIN_INITIAL_DEPOSIT, "total supply");

        assertEq(vault.balanceOf(address(factory)), 1e3, "factory gets 1e3 shares");
        assertEq(vault.balanceOf(address(this)), MIN_INITIAL_DEPOSIT - 1e3, "deployer gets 1e3 less shares");
    }

    function test_CreateVault_SameBytecodeDifferentSalt() public {
        bytes32 salt = _getSalt(address(this), "random salt");

        Vault vault = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );

        setERC20Balance(address(BASE_ASSET), address(this), MIN_INITIAL_DEPOSIT);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);

        bytes32 salt2 = _getSalt(address(this), "second random salt");
        Vault vault2 = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt2,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );

        assertEq(VAULT_ADMIN, vault.defaultAdmin(), "default admin");
        assertEq(feeRecipient, vault.feeRecipient(), "fee recipient");
        assertEq(address(baseAsset), address(vault.BASE_ASSET()), "base asset");

        assertEq(VAULT_ADMIN, vault2.defaultAdmin(), "default admin");
        assertEq(feeRecipient, vault2.feeRecipient(), "fee recipient");
        assertEq(address(baseAsset), address(vault2.BASE_ASSET()), "base asset");
    }

    function test_Revert_CreateVault_SameSaltTwice() public {
        bytes32 salt = _getSalt(address(this), "random salt");

        Vault vault = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );

        vm.expectRevert();
        Vault vault2 = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );
    }

    function test_Revert_SaltMustBeginWithMsgSender() public {
        bytes32 salt = _getSalt(address(1), "random salt");
        require(address(this) != address(1));

        vm.expectRevert(VaultFactory.SaltMustBeginWithMsgSender.selector);
        Vault vault = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );
    }

    /**
     * If the salt begins with the same sender, but the ending bytes are
     * different, it should deploy to different addresses.
     */
    function test_Revert_SaltBeginsWithMsgSenderButDiffEnding() public {
        bytes32 salt1 = _getSalt(address(this), "first random salt");
        bytes32 salt2 = _getSalt(address(this), "second random salt");

        require(salt1 != salt2, "salt must be different");

        deal(address(BASE_ASSET), address(this), MIN_INITIAL_DEPOSIT);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);
        Vault vault1 = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt1,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );

        deal(address(BASE_ASSET), address(this), MIN_INITIAL_DEPOSIT);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);
        Vault vault2 = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt2,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );

        assertTrue(address(vault1) != address(vault2), "deployment addresses must be different");
    }

    function test_CreateVault_SameSaltDifferentBytecode() public {
        bytes32 salt = _getSalt(address(this), "random salt");

        Vault vault = factory.createVault(
            BASE_ASSET,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );

        // Deploy a vault with different base assets
        IERC20 diffBaseAsset = IERC20(address(new ERC20PresetMinterPauser("Another Wrapped Staked ETH", "wstETH2")));

        IIonPool[] memory markets = new IIonPool[](3);
        markets[0] = deployIonPool(diffBaseAsset, WEETH, address(this));
        markets[1] = deployIonPool(diffBaseAsset, RSETH, address(this));
        markets[2] = deployIonPool(diffBaseAsset, RSWETH, address(this));

        marketsArgs.marketsToAdd = markets;
        marketsArgs.allocationCaps = allocationCaps;
        marketsArgs.newSupplyQueue = markets;
        marketsArgs.newWithdrawQueue = markets;

        setERC20Balance(address(diffBaseAsset), address(this), MIN_INITIAL_DEPOSIT);
        diffBaseAsset.approve(address(factory), MIN_INITIAL_DEPOSIT);

        Vault vault2 = factory.createVault(
            diffBaseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );

        require(address(vault) != address(vault2), "different deployment address");
    }

    /**
     * The amount of funds that the attacker can cause the user to lose should
     * cost the attacker a significant amount of funds.
     */
    function test_InflationAttackCostToGriefShouldBeHigh_DeployerIsNotTheAttacker() public {
        uint256[] memory alloCaps = new uint256[](4);
        alloCaps[0] = type(uint256).max;
        alloCaps[1] = type(uint256).max;
        alloCaps[2] = type(uint256).max;
        alloCaps[3] = type(uint256).max;

        IIonPool[] memory markets = new IIonPool[](4);
        markets[0] = IDLE;
        markets[1] = weEthIonPool;
        markets[2] = rsEthIonPool;
        markets[3] = rswEthIonPool;

        marketsArgs.marketsToAdd = markets;
        marketsArgs.allocationCaps = alloCaps;
        marketsArgs.newSupplyQueue = markets;
        marketsArgs.newWithdrawQueue = markets;

        address deployer = newAddress("DEPLOYER");
        // deploy using the factory which enforces minimum deposit of 1e9 assets
        // and the 1e3 shares burn.
        bytes32 salt = _getSalt(deployer, "random salt");

        setERC20Balance(address(BASE_ASSET), deployer, MIN_INITIAL_DEPOSIT);

        vm.startPrank(deployer);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);

        Vault vault = factory.createVault(
            BASE_ASSET,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            salt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );
        vm.stopPrank();

        vm.startPrank(VAULT_ADMIN);
        vault.grantRole(vault.OWNER_ROLE(), OWNER);
        vm.stopPrank();

        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        uint256 donationAmt = 10e18;
        uint256 mintAmt = 10;

        // fund attacker
        setERC20Balance(address(BASE_ASSET), address(this), donationAmt + mintAmt);
        BASE_ASSET.approve(address(vault), type(uint256).max);

        uint256 initialAssetBalance = BASE_ASSET.balanceOf(address(this));
        console2.log("attacker balance before :");
        console2.log("%e", initialAssetBalance);

        vault.mint(mintAmt, address(this));
        uint256 attackerClaimAfterMint = vault.previewRedeem(vault.balanceOf(address(this)));

        console2.log("attackerClaimAfterMint: ");
        console2.log("%e", attackerClaimAfterMint);

        console2.log("donationAmt: ");
        console2.log("%e", donationAmt);

        // donate to inflate exchange rate by increasing `totalAssets`
        IERC20(address(BASE_ASSET)).transfer(address(vault), donationAmt);

        assertEq(donationAmt + mintAmt + 1e3, vault.totalAssets(), "total assets");
        assertEq(mintAmt + 1e3, vault.totalSupply(), "minted shares");

        // how much of this donation was captured by the virtual shares on the vault?
        uint256 attackerClaimAfterDonation = vault.previewRedeem(vault.balanceOf(address(this)));

        console2.log("attackerClaimAfterDonation: ");
        console2.log("%e", attackerClaimAfterDonation);

        uint256 lossFromDonation = attackerClaimAfterMint + donationAmt - attackerClaimAfterDonation;

        console2.log("loss from donation: ");
        console2.log("%e", lossFromDonation);

        address alice = address(0xabcd);
        setERC20Balance(address(BASE_ASSET), alice, 10e18 + 10);

        vm.startPrank(alice);
        IERC20(address(BASE_ASSET)).approve(address(vault), 1e18);
        vault.deposit(1e18, alice);
        vm.stopPrank();

        // Alice gained zero shares due to exchange rate inflation
        uint256 aliceShares = vault.balanceOf(alice);
        console2.log("alice resulting shares : ");
        console2.log("%e", aliceShares);

        uint256 aliceClaim = vault.maxWithdraw(alice);
        console2.log("alice resulting claim: ");
        console2.log("%e", aliceClaim);

        console2.log("alice resulting assets lost: ");
        console2.log("%e", 1e18 - aliceClaim);

        // How much of alice's deposits were captured by the attacker's shares?
        uint256 attackerClaimAfterAlice = vault.previewRedeem(vault.balanceOf(address(this)));
        uint256 attackerGainFromAlice = attackerClaimAfterAlice - attackerClaimAfterDonation;
        console2.log("attackerGainFromAlice: ");
        console2.log("%e", attackerGainFromAlice);

        vault.redeem(vault.balanceOf(address(this)) - 3, address(this), address(this));
        uint256 afterAssetBalance = BASE_ASSET.balanceOf(address(this));

        console2.log("attacker balance after : ");
        console2.log("%e", afterAssetBalance);

        console2.log("attacker loss in balance");
        console2.log("%e", initialAssetBalance - afterAssetBalance);

        assertLe(attackerGainFromAlice, lossFromDonation, "attack must not be profitable");
        assertLe(afterAssetBalance, initialAssetBalance, "attacker must not be profitable");
        assertLe(1e18, initialAssetBalance - afterAssetBalance, "attacker loss greater than amount griefed");
    }

    function test_Revert_Create2FrontrunSameConstructorArgDiffMsgSender() public {
        address deployer = newAddress("DEPLOYER");
        address attacker = newAddress("ATTACKER");

        deal(address(BASE_ASSET), deployer, MIN_INITIAL_DEPOSIT);
        deal(address(BASE_ASSET), attacker, MIN_INITIAL_DEPOSIT);

        bytes32 deployerSalt = _getSalt(deployer, "random salt");

        vm.startPrank(deployer);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);
        Vault deployerVault = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            deployerSalt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );
        vm.stopPrank();

        vm.startPrank(attacker);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);
        vm.expectRevert(); // create collision
        Vault attackerVault = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            deployerSalt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );
        vm.stopPrank();
    }

    /**
     * Deployed with the same salt, but because the `feeRecipient` input address
     * was changed, the attacker transaction deploys to a different address.
     */
    function test_Create2FrontrunDifferentConstructorArgsAndDifferentSalt() public {
        address deployer = newAddress("DEPLOYER");
        address attacker = newAddress("ATTACKER");

        deal(address(BASE_ASSET), deployer, MIN_INITIAL_DEPOSIT);
        deal(address(BASE_ASSET), attacker, MIN_INITIAL_DEPOSIT);

        bytes32 deployerSalt = _getSalt(deployer, "random");
        bytes32 attackerSalt = _getSalt(attacker, "random");

        vm.startPrank(deployer);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);
        Vault deployerVault = factory.createVault(
            baseAsset,
            feeRecipient,
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            deployerSalt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );
        vm.stopPrank();

        vm.startPrank(attacker);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);
        Vault attackerVault = factory.createVault(
            baseAsset,
            newAddress("ATTACKER_FRONTRUN_FEE_RECIPIENT"),
            feePercentage,
            name,
            symbol,
            INITIAL_DELAY,
            VAULT_ADMIN,
            attackerSalt,
            marketsArgs,
            MIN_INITIAL_DEPOSIT
        );
        vm.stopPrank();

        assertTrue(address(deployerVault) != address(attackerVault), "different deployment address");
    }
}
