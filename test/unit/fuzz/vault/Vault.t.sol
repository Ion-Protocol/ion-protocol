// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IIonPool } from "./../../../../src/interfaces/IIonPool.sol";
import { IonPoolExposed } from "../../../helpers/IonPoolSharedSetup.sol";
import { VaultSharedSetup } from "../../../helpers/VaultSharedSetup.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import { WadRayMath, RAY, WAD } from "./../../../../src/libraries/math/WadRayMath.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

using Math for uint256;

contract Vault_Fuzz is VaultSharedSetup {
    function setUp() public override {
        super.setUp();

        BASE_ASSET.approve(address(weEthIonPool), type(uint256).max);
        BASE_ASSET.approve(address(rsEthIonPool), type(uint256).max);
        BASE_ASSET.approve(address(rswEthIonPool), type(uint256).max);
    }

    /*
     * Confirm rounding error max bound
     * error = asset - floor[asset * RAY - (asset * RAY) % SF] / RAY)
     * Considering the modulos, this error value is max bounded to
     * max bound error = (SF - 2) / RAY + 1
     * NOTE: While this passes, the expression with SF - 3 also passes, so not
     * yet a guarantee that this is the tightest bound possible. 
     */
    function testFuzz_IonPoolSupplyRoundingError(uint256 assets, uint256 supplyFactor) public {
        assets = bound(assets, 1e18, type(uint128).max);
        supplyFactor = bound(supplyFactor, 1e27, assets * RAY);

        setERC20Balance(address(BASE_ASSET), address(this), assets);

        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        weEthIonPool.supply(address(this), assets, new bytes32[](0));

        uint256 expectedClaim = assets;
        uint256 resultingClaim = weEthIonPool.balanceOf(address(this));

        uint256 re = assets - ((assets * RAY - ((assets * RAY) % supplyFactor)) / RAY);
        assertLe(expectedClaim - resultingClaim, (supplyFactor - 2) / RAY + 1);
    }

    function testFuzz_FullyWithdrawableFromIonPool(uint256 assets) public {
        uint256 supplyFactor = bound(assets, 1e27, 10e45);
        uint256 normalizedAmt = bound(assets, 0, type(uint48).max);

        uint256 claim = normalizedAmt * supplyFactor / RAY;
        uint256 sharesToBurn = claim * RAY / supplyFactor;
        sharesToBurn = sharesToBurn * supplyFactor < claim * RAY ? sharesToBurn + 1 : sharesToBurn;

        assertEq(normalizedAmt, sharesToBurn);
    }
}

contract VaultWithYieldAndFee_Fuzz is VaultSharedSetup {
    uint256 constant INITIAL_SUPPLY_AMT = 1000e18;

    function setUp() public override {
        super.setUp();

        uint256 initialSupplyAmt = 1000e18;

        weEthIonPool.updateSupplyCap(type(uint256).max);
        rsEthIonPool.updateSupplyCap(type(uint256).max);
        rswEthIonPool.updateSupplyCap(type(uint256).max);

        weEthIonPool.updateIlkDebtCeiling(0, type(uint256).max);
        rsEthIonPool.updateIlkDebtCeiling(0, type(uint256).max);
        rswEthIonPool.updateIlkDebtCeiling(0, type(uint256).max);

        supply(address(this), weEthIonPool, INITIAL_SUPPLY_AMT);
        borrow(address(this), weEthIonPool, weEthGemJoin, 100e18, 70e18);

        supply(address(this), rsEthIonPool, INITIAL_SUPPLY_AMT);
        borrow(address(this), rsEthIonPool, rsEthGemJoin, 100e18, 70e18);

        supply(address(this), rswEthIonPool, INITIAL_SUPPLY_AMT);
        borrow(address(this), rswEthIonPool, rswEthGemJoin, 100e18, 70e18);

        uint256 weEthIonPoolCap = 10e18;
        uint256 rsEthIonPoolCap = 20e18;
        uint256 rswEthIonPoolCap = 30e18;

        vm.prank(OWNER);
        updateAllocationCaps(vault, weEthIonPoolCap, rsEthIonPoolCap, rswEthIonPoolCap);
    }

    function testFuzz_AccruedFeeShares(uint256 initialDeposit, uint256 feePerc, uint256 daysAccrued) public {
        // fee percentage
        feePerc = bound(feePerc, 0, RAY - 1);

        vm.prank(OWNER);
        vault.updateFeePercentage(feePerc);

        // initial deposit
        uint256 initialMaxDeposit = vault.maxDeposit(NULL);
        initialDeposit = bound(initialDeposit, 1e18, initialMaxDeposit);

        setERC20Balance(address(BASE_ASSET), address(this), initialDeposit);
        vault.deposit(initialDeposit, address(this));

        // initial state
        uint256 prevTotalAssets = vault.totalAssets();
        uint256 prevUserShares = vault.balanceOf(address(this));
        uint256 prevUserAssets = vault.previewRedeem(prevUserShares);

        // interest accrues over a year
        daysAccrued = bound(daysAccrued, 1, 10_000 days);
        vm.warp(block.timestamp + daysAccrued);

        (uint256 totalSupplyFactorIncrease,,,,) = weEthIonPool.calculateRewardAndDebtDistribution();
        uint256 newTotalAssets = vault.totalAssets();
        uint256 interestAccrued = newTotalAssets - prevTotalAssets; // [WAD]

        assertGt(totalSupplyFactorIncrease, 0, "total supply factor increase");
        assertGt(vault.totalAssets(), prevTotalAssets, "total assets increased");
        assertGt(interestAccrued, 0, "interest accrued");

        // expected resulting state

        uint256 expectedFeeAssets = interestAccrued.mulDiv(feePerc, RAY);
        uint256 expectedFeeShares =
            expectedFeeAssets.mulDiv(vault.totalSupply(), newTotalAssets - expectedFeeAssets, Math.Rounding.Floor);

        uint256 expectedUserAssets = prevUserAssets + interestAccrued.mulDiv(RAY - feePerc, RAY);

        vm.prank(OWNER);
        vault.accrueFee();
        assertEq(vault.lastTotalAssets(), vault.totalAssets(), "last total assets updated");

        // actual resulting values
        uint256 feeRecipientShares = vault.balanceOf(FEE_RECIPIENT);
        uint256 feeRecipientAssets = vault.previewRedeem(feeRecipientShares);

        uint256 userShares = vault.balanceOf(address(this));
        uint256 userAssets = vault.previewRedeem(userShares);

        // fee recipient
        // 1. The actual shares minted must be exactly equal to the expected
        // shares calculation.
        // 2. The actual claim from previewRedeem versus the expected claim to the
        // underlying assets will differ due to the vault rounding in its favor
        // inside the `preview` calculation. Even though the correct number of
        // shares were minted, the actual 'withdrawable' amount will be rounded
        // down in vault's favor. The actual must always be less than expected.
        assertEq(feeRecipientShares, expectedFeeShares, "fee shares");
        assertLe(expectedFeeAssets - feeRecipientAssets, 2, "fee assets with rounding error");

        // the diluted user
        // Expected to increase their assets by (interestAccrued * (1 - feePerc))
        // 1. The shares balance for the user does not change.
        // 2. The withdrawable assets after the fee should have increased by
        // their portion of interest accrued.
        assertEq(userShares, prevUserShares, "user shares");
        // Sometimes userAssets > expectedUserAssets, sometimes less than.
        assertApproxEqAbs(userAssets, expectedUserAssets, 1, "user assets");

        // fee recipient and user
        // 1. The user and the fee recipient are the only shareholders.
        // 2. The total withdrawable by the user and the fee recipient should equal total assets.
        assertEq(userShares + feeRecipientShares, vault.totalSupply(), "vault total supply");
        assertLe(vault.totalAssets() - (userAssets + feeRecipientAssets), 2, "vault total assets");
    }

    function testFuzz_MaxWithdrawAndMaxRedeem(uint256 assets) public { }

    function testFuzz_MaxDepositAndMaxMint(uint256 assets) public { }
}

contract VaultInflationAttack is VaultSharedSetup {
    address immutable ATTACKER = newAddress("attacker");
    address immutable USER = newAddress("user");

    function setUp() public override {
        super.setUp();

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

        vm.prank(ATTACKER);
        IERC20(address(BASE_ASSET)).approve(address(vault), type(uint256).max);
        vm.prank(USER);
        IERC20(address(BASE_ASSET)).approve(address(vault), type(uint256).max);
    }

    function testFuzz_InflationAttackNotProfitable(uint256 assets) public {
        // 1. The vault has not been used.
        // - no shares minted and no assets deposited.
        // - but the initial conversion is dictated by virtual shares.
        assertEq(vault.totalSupply(), 0, "initial total supply");
        assertEq(vault.totalAssets(), 0, "initial total assets");

        // 2. The attacker makes a first deposit.
        uint256 firstDepositAmt = bound(assets, 0, type(uint128).max);
        setERC20Balance(address(BASE_ASSET), ATTACKER, firstDepositAmt);

        vm.prank(ATTACKER);
        vault.mint(firstDepositAmt, ATTACKER);

        uint256 attackerClaimAfterMint = vault.previewRedeem(vault.balanceOf(ATTACKER));

        // check that the mint amount and transfer amount was the same
        assertEq(BASE_ASSET.balanceOf(ATTACKER), 0, "mint amount equals transfer amount");

        // 3. The attacker donates.
        // - In this case, transfers to vault to increase IDLE deposits.
        // - Check that the attacker loses a portion of the donated funds.
        uint256 donationAmt = bound(assets, 0, type(uint128).max);
        setERC20Balance(address(BASE_ASSET), ATTACKER, donationAmt);

        vm.prank(ATTACKER);
        IERC20(address(BASE_ASSET)).transfer(address(vault), donationAmt);

        uint256 attackerClaimAfterDonation = vault.previewRedeem(vault.balanceOf(ATTACKER));
        uint256 attackerLossFromDonation = donationAmt - (attackerClaimAfterDonation - attackerClaimAfterMint);

        uint256 totalAssetsBeforeDeposit = vault.totalAssets();
        uint256 totalSupplyBeforeDeposit = vault.totalSupply();

        // 4. A user makes a deposit where the shares truncate to zero.
        // - sharesToMint = depositAmt * (newTotalSupply + 1) / (newTotalAssets + 1)
        // - The sharesToMint must be less than 1 to round down to zero
        //     - depositAmt * (newTotalSupply + 1) / (newTotalAssets + 1) < 1
        //     - depositAmt < 1 * (newTotalAssets + 1) / (newTotalSupply + 1)
        uint256 maxDepositAmt = (vault.totalAssets() + 1) / (vault.totalSupply() + 1);
        uint256 userDepositAmt = bound(assets, 0, maxDepositAmt);

        vm.startPrank(USER);
        setERC20Balance(address(BASE_ASSET), USER, userDepositAmt);
        IERC20(address(BASE_ASSET)).approve(address(vault), userDepositAmt);
        vault.deposit(userDepositAmt, USER);
        vm.stopPrank();

        assertEq(vault.balanceOf(USER), 0, "user minted shares must be zero");

        uint256 attackerClaimAfterUser = vault.previewRedeem(vault.balanceOf(ATTACKER));
        uint256 attackerGainFromUser = attackerClaimAfterUser - attackerClaimAfterDonation;

        // loss = donationAmt / (1 + firstDepositAmt)
        uint256 expectedAttackerLossFromDonation = donationAmt / (1 + firstDepositAmt);
        assertLe(
            attackerLossFromDonation - expectedAttackerLossFromDonation,
            1,
            "attacker loss from donation as expected with rounding error"
        );

        // INVARIANT: The money gained from the user must be less than or equal to the attacker's loss from the
        // donation.
        // assertLe(attackerGainFromUser, attackerLossFromDonation, "attacker must not profit from user");
        assertLe(userDepositAmt, attackerLossFromDonation, "loss must be ge to user deposit");
    }

    function testFuzz_InflationAttackSmallerDegree() public { }
}
