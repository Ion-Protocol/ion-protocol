// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Vault } from "./../../../../src/vault/Vault.sol";
import { VaultFactory } from "./../../../../src/vault/VaultFactory.sol";
import { IIonPool } from "./../../../../src/interfaces/IIonPool.sol";
import { IonPoolExposed } from "../../../helpers/IonPoolSharedSetup.sol";
import { VaultSharedSetup } from "../../../helpers/VaultSharedSetup.sol";
import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import { WadRayMath, RAY } from "./../../../../src/libraries/math/WadRayMath.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

using Math for uint256;
using WadRayMath for uint256;

import { console2 } from "forge-std/console2.sol";

contract Vault_Fuzz is VaultSharedSetup {
    using Math for uint256;

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

    // NOTE Supplying the diff can revert if the normalized mint amount
    // truncates to zero. Otherwise, it should be impossible to supply the
    // 'diff' and end up violating the supply cap.

    function testFuzz_DepositToFillSupplyCap(uint256 assets, uint256 supplyFactor) public {
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        uint256 supplyCap = bound(assets, 100e18, type(uint128).max);
        weEthIonPool.updateSupplyCap(supplyCap);

        uint256 initialDeposit = bound(assets, 1e18, supplyCap - 10e18);
        supply(address(this), weEthIonPool, initialDeposit);
        uint256 initialTotalNormalized = weEthIonPool.normalizedTotalSupply();

        uint256 supplyCapDiff = _zeroFloorSub(supplyCap, weEthIonPool.totalSupply());

        // `IonPool.supply` math
        uint256 amountScaled = supplyCapDiff.rayDivDown(supplyFactor);
        uint256 resultingTotalNormalized = initialTotalNormalized + amountScaled;

        uint256 resultingTotalClaim = resultingTotalNormalized.rayMulDown(supplyFactor);

        supply(address(this), weEthIonPool, supplyCapDiff);

        assertEq(resultingTotalClaim, weEthIonPool.totalSupply(), "resulting should be the same as calculated");

        // Is it possible that depositing this supplyCapDiff results in a revert?
        // `IonPool` compares `getTotalUnderlyingClaims > _supplyCap`
        assertLe(resultingTotalClaim, supplyCap, "supply cap reached");
        assertLe(weEthIonPool.totalSupply(), supplyCap, "supply cap reached");
    }

    // Supplying the diff in the allocation cap should never end up violating
    // the allocation cap.
    // Is it possible that the `maxDeposit` returns more than the allocation cap?
    function testFuzz_DepositToFillAllocationCap(uint256 assets, uint256 supplyFactor) public {
        supplyFactor = bound(supplyFactor, 1e27, 9e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        uint256 allocationCap = bound(assets, 100e18, type(uint128).max);
        updateAllocationCaps(vault, allocationCap, type(uint128).max, 0);

        // Deposit, but leave some room below the allocation cap.
        uint256 depositAmt = bound(assets, 1e18, allocationCap - 10e18);
        setERC20Balance(address(BASE_ASSET), address(this), depositAmt);
        vault.deposit(depositAmt, address(this));

        // uint256 initialTotalNormalized = weEthIonPool.totalSupplyUnaccrued();
        uint256 initialTotalNormalized = weEthIonPool.normalizedTotalSupply();

        uint256 allocationCapDiff = _zeroFloorSub(allocationCap, weEthIonPool.balanceOf(address(vault)));

        uint256 amountScaled = allocationCapDiff.rayDivDown(supplyFactor);
        uint256 resultingTotalNormalized = initialTotalNormalized + amountScaled;
        uint256 resultingTotalClaim = resultingTotalNormalized.rayMulDown(supplyFactor);

        // Try to deposit a little more than the first allocation cap would
        // allow, then check whether it's possible to violate the first
        // allocation cap.

        setERC20Balance(address(BASE_ASSET), address(this), allocationCapDiff + 123e18);
        vault.deposit(allocationCapDiff + 123e18, address(this));

        uint256 actualTotalClaim = weEthIonPool.balanceOf(address(vault));
        assertEq(resultingTotalClaim, actualTotalClaim, "expected and actual must be equal");

        assertLe(resultingTotalClaim, allocationCap, "expected claim le to allocation cap");
        assertLe(actualTotalClaim, allocationCap, "actual claim le to allocation cap");
    }

    /**
     * Should confirm that maxBound is the true maxBound.
     * - If maxBound is increased by one, then the equals assert should fail.
     */
    function testFuzz_MaximumDepositAmountThatTruncatesToZeroNormalized(uint256 assets, uint256 supplyFactor) public {
        supplyFactor = bound(supplyFactor, 1e27, type(uint256).max);

        // this amount should always trunate to zero after division
        // ceil(supplyFactor / RAY) - 1 passes [correctly constrained]
        // ceil(supplyFactor / RAY) does not pass
        uint256 divRoundUp = supplyFactor % RAY == 0 ? supplyFactor / RAY : supplyFactor / RAY + 1;
        uint256 assetsMaxBound = divRoundUp - 1; // supplyFactor / RAY - 1 passes but overconstrained?

        assets = bound(assets, 0, assetsMaxBound);

        uint256 normalized = assets.mulDiv(RAY, supplyFactor);

        assertEq(normalized, 0, "normalized must be zero");
    }

    /**
     * Assume `supplyFactor` is less than 2e27.
     * 1. If `supplyFactor` is 2e27, the maxBound ceil(2e27 / 1e27) - 1 = 1.
     * This means anything above 1 wei will not truncate to zero.
     * 2. If `supplyFactor` is 2e27 - 1, the maxBound ceil((2e27 - 1) / 1e27) - 1 is 1.
     * This means the maxBound is 1. So anything above 1 (i.e. 2 and above)
     * should not normalize to zero.
     */
    function testFuzz_MaximumDepositAmountThatTruncatesWhenSupplyFactorIsLessThanTwoRay(
        uint256 assets,
        uint256 supplyFactor
    )
        public
    {
        supplyFactor = bound(supplyFactor, 1e27, 2e27);
        assets = bound(assets, 2, type(uint256).max);

        // all assets amount other than 0 will NOT truncate to zero.
        uint256 normalized = assets.mulDiv(RAY, supplyFactor);

        assertTrue(normalized != 0, "normalized must NOT be zero");
    }

    /**
     * If `assets` is not 0, then the result of the muldiv should never be 0 due
     * to the ceiling.
     */
    function testFuzz_MulDivCeilingCanNotBeZero(uint256 assets, uint256 supplyFactor) public {
        assets = bound(assets, 1, type(uint128).max);
        supplyFactor = bound(supplyFactor, 1, type(uint128).max);

        uint256 result = assets.mulDiv(RAY, supplyFactor, Math.Rounding.Ceil);

        assertTrue(result != 0, "result must NOT be zero");
    }
}

contract VaultWithYieldAndFeeSharedSetup is VaultSharedSetup {
    uint256 constant INITIAL_SUPPLY_AMT = 1000e18;
    uint256 constant MAX_DAYS = 10_000 days;
    uint256 constant MINIMUM_FEE_PERC = 0.02e27;
    uint256 constant MAXIMUM_FEE_PERC = 1e27;

    uint256 constant MINIMUM_INITIAL_DEPOSIT = 0;
    uint256 constant MAXIMUM_INITIAL_DEPOSIT = type(uint128).max;

    IIonPool[] internal queue = new IIonPool[](4);

    function setUp() public virtual override {
        super.setUp();

        IIonPool[] memory marketsToAdd = new IIonPool[](1);
        marketsToAdd[0] = IDLE;

        uint256[] memory newMarketAllocationCap = new uint256[](1);
        newMarketAllocationCap[0] = 0;

        queue[0] = IDLE;
        queue[1] = weEthIonPool;
        queue[2] = rsEthIonPool;
        queue[3] = rswEthIonPool;

        vm.prank(OWNER);
        vault.addSupportedMarkets(marketsToAdd, newMarketAllocationCap, queue, queue);

        uint256[] memory allocationCaps = new uint256[](4);
        allocationCaps[0] = 10e18;
        allocationCaps[1] = 20e18;
        allocationCaps[2] = 30e18;
        allocationCaps[3] = 40e18;

        vm.prank(OWNER);
        vault.updateAllocationCaps(queue, allocationCaps);

        // Setup IonPools
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
    }
}

contract VaultWithYieldAndFee_Fuzz_FeeAccrual is VaultWithYieldAndFeeSharedSetup {
    function testFuzz_AccruedFeeShares(uint256 initialDeposit, uint256 feePerc, uint256 daysAccrued) public {
        // fee percentage
        feePerc = bound(feePerc, 0, RAY - 1);

        vm.prank(OWNER);
        vault.updateFeePercentage(feePerc);

        // initial deposit
        uint256 initialMaxDeposit = vault.maxDeposit(NULL);
        initialDeposit = bound(initialDeposit, 15e18, initialMaxDeposit);

        setERC20Balance(address(BASE_ASSET), address(this), initialDeposit);
        vault.deposit(initialDeposit, address(this));

        // initial state
        uint256 prevTotalAssets = vault.totalAssets();
        uint256 prevUserShares = vault.balanceOf(address(this));
        uint256 prevUserAssets = vault.previewRedeem(prevUserShares);

        // interest accrues over a year
        daysAccrued = bound(daysAccrued, 1, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        (uint256 totalSupplyFactorIncrease,,,,) = weEthIonPool.calculateRewardAndDebtDistribution();
        uint256 newTotalAssets = vault.totalAssets();
        uint256 interestAccrued = newTotalAssets - prevTotalAssets; // [WAD]

        assertGt(totalSupplyFactorIncrease, 0, "total supply factor increase");
        assertGt(vault.totalAssets(), prevTotalAssets, "total assets increased");
        assertGt(interestAccrued, 0, "interest accrued");

        // expected resulting state

        uint256 expectedFeeAssets = interestAccrued.mulDiv(feePerc, RAY);
        uint256 expectedFeeShares = expectedFeeAssets.mulDiv(
            vault.totalSupply() + 1, newTotalAssets - expectedFeeAssets + 1, Math.Rounding.Floor
        );

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
}

contract VaultWithYieldAndFee_Fuzz_Previews_SinglePool is VaultWithYieldAndFeeSharedSetup {
    function setUp() public override {
        super.setUp();

        // Only funnel deposits into one IonPool that's not IDLE.
        uint256[] memory allocationCaps = new uint256[](4);
        allocationCaps[0] = 0;
        allocationCaps[1] = type(uint128).max;
        allocationCaps[2] = 0;
        allocationCaps[3] = 0;

        vm.prank(OWNER);
        vault.updateAllocationCaps(queue, allocationCaps);
    }

    function testFuzz_previewDeposit_SinglePool(
        uint256 assets,
        uint256 feePerc,
        uint256 daysAccrued,
        uint256 supplyFactor
    )
        public
    {
        // 1. Set `supplyFactor`
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        // 2. Make initial vault deposit
        uint256 initialDeposit = bound(assets, MINIMUM_INITIAL_DEPOSIT, vault.maxDeposit(NULL));
        deal(address(BASE_ASSET), address(this), initialDeposit);
        vault.deposit(initialDeposit, address(this));

        // 3. Set fee percentage
        feePerc = bound(feePerc, MINIMUM_FEE_PERC, MAXIMUM_FEE_PERC);

        vm.prank(OWNER);
        vault.updateFeePercentage(feePerc);

        // 4. Accrue interest
        daysAccrued = bound(daysAccrued, 100 days, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        // 5. Compare preview deposit with real deposit
        // - Minimum deposit amount is amount that won't be truncated by zer
        // - amt * RAY / supplyFactor > 0
        uint256 minimumDeposit = RAY / vault.supplyQueue(1).supplyFactor() + 1;
        uint256 previewDepositAmt = bound(assets, 0, vault.maxDeposit(NULL));

        console2.log("vault.maxDeposit(NULL): ", vault.maxDeposit(NULL));
        console2.log("previewDepositAmt: ", previewDepositAmt);

        console2.log("--- preview deposit ---");
        uint256 expectedShares = vault.previewDeposit(previewDepositAmt);
        console2.log("--- preview deposit done ---");

        deal(address(BASE_ASSET), address(this), previewDepositAmt);
        uint256 resultingShares = vault.deposit(previewDepositAmt, address(this));

        uint256 resultingAssets = vault.previewRedeem(resultingShares);

        uint256 resultingAssetsRoundingError = vault.supplyQueue(1).supplyFactor() / RAY + 1;

        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "resulting user asset balance");
        assertEq(resultingShares, expectedShares, "resulting shares must be equal to expected shares");
        assertApproxEqAbs(
            resultingAssets, previewDepositAmt, resultingAssetsRoundingError, "resulting assets with rounding error"
        );
    }

    function testFuzz_previewMint_SinglePool(
        uint256 assets,
        uint256 feePerc,
        uint256 daysAccrued,
        uint256 supplyFactor
    )
        public
    {
        // 1. Set `supplyFactor`
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        // 2. Make initial vault deposit
        uint256 initialDeposit = bound(assets, MINIMUM_INITIAL_DEPOSIT, vault.maxDeposit(NULL));
        deal(address(BASE_ASSET), address(this), initialDeposit);
        vault.deposit(initialDeposit, address(this));

        // 3. Set fee percentage
        feePerc = bound(feePerc, MINIMUM_FEE_PERC, MAXIMUM_FEE_PERC);

        // 4. Accrue interest
        daysAccrued = bound(daysAccrued, 100 days, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        // 5. Compare `previewMint` with `mint`

        uint256 previewMintAmt = bound(assets, 0, vault.maxMint(NULL));

        uint256 expectedAssets = vault.previewMint(previewMintAmt);

        uint256 prevShares = vault.balanceOf(address(this));

        deal(address(BASE_ASSET), address(this), expectedAssets);
        uint256 resultingAssets = vault.mint(previewMintAmt, address(this));

        uint256 sharesDiff = vault.balanceOf(address(this)) - prevShares;

        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "resulting user asset balance");
        assertEq(resultingAssets, expectedAssets, "resulting assets must be equal to expected assets");
        assertEq(sharesDiff, previewMintAmt, "resulting shares must be equal to preview mint amount");
    }

    function testFuzz_previewWithdraw_SinglePool(
        uint256 assets,
        uint256 feePerc,
        uint256 daysAccrued,
        uint256 supplyFactor
    )
        public
    {
        // 1. Set `supplyFactor`
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        // 2. Make initial vault deposit
        require(vault.maxDeposit(NULL) > 0);
        uint256 initialDeposit = bound(assets, MINIMUM_INITIAL_DEPOSIT, vault.maxDeposit(NULL));
        deal(address(BASE_ASSET), address(this), initialDeposit);
        vault.deposit(initialDeposit, address(this));

        // require(vault.balanceOf(address(this)) > 0, 'shares minted');

        // 3. Set fee percentage
        feePerc = bound(feePerc, MINIMUM_FEE_PERC, MAXIMUM_FEE_PERC);

        // 4. Accrue interest
        daysAccrued = bound(daysAccrued, 100 days, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        // 5. Compoare `previewWithdraw` and `withdraw`
        uint256 previewWithdrawAmt = bound(assets, 0, vault.maxWithdraw(address(this)));
        uint256 expectedShares = vault.previewWithdraw(previewWithdrawAmt);

        uint256 prevShares = vault.balanceOf(address(this));
        uint256 prevBalance = BASE_ASSET.balanceOf(address(this));

        uint256 resultingShares = vault.withdraw(previewWithdrawAmt, address(this), address(this));

        uint256 sharesDiff = prevShares - vault.balanceOf(address(this));
        uint256 balanceDiff = BASE_ASSET.balanceOf(address(this)) - prevBalance;

        assertEq(sharesDiff, resultingShares, "actual shares diff should be equal to the returned shares");
        assertEq(resultingShares, expectedShares, "resulting shares must be equal to preview shares");
        assertEq(balanceDiff, previewWithdrawAmt, "resulting balance should be the exact request withdraw amount");
    }

    function testFuzz_previewRedeem_SinglePool(
        uint256 assets,
        uint256 feePerc,
        uint256 daysAccrued,
        uint256 supplyFactor
    )
        public
    {
        // 1. Set `supplyFactor`
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        // 2. Make initial vault deposit
        uint256 initialDeposit = bound(assets, MINIMUM_INITIAL_DEPOSIT, vault.maxDeposit(NULL));
        deal(address(BASE_ASSET), address(this), initialDeposit);
        vault.deposit(initialDeposit, address(this));

        // 3. Set fee percentage
        feePerc = bound(feePerc, MINIMUM_FEE_PERC, MAXIMUM_FEE_PERC);

        // 4. Accrue interest
        daysAccrued = bound(daysAccrued, 100 days, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        // 5. Compare `previewRedeem` and `redeem`
        uint256 prevShares = vault.balanceOf(address(this));

        uint256 previewRedeemAmt = bound(assets, 0, vault.maxRedeem(address(this)));
        uint256 expectedAssets = vault.previewRedeem(previewRedeemAmt);

        uint256 resultingAssets = vault.redeem(previewRedeemAmt, address(this), address(this));

        uint256 sharesDiff = prevShares - vault.balanceOf(address(this));

        assertEq(resultingAssets, expectedAssets, "resulting assets must be equal to expected assets");
        assertEq(sharesDiff, previewRedeemAmt, "shares burned must be equal to redeem amount");
    }
}

contract VaultWithYieldAndFee_Fuzz_Previews_MultiplePools is VaultWithYieldAndFeeSharedSetup {
    /**
     * Fuzz variables
     * - `supplyFactor`
     * - `newTotalAssets` (through interest accrual)
     * - `feeShares` minted (through fee percentage)
     */
    function testFuzz_previewDeposit_MultiplePools(
        uint256 assets,
        uint256 feePerc,
        uint256 daysAccrued,
        uint256 supplyFactor
    )
        public
    {
        // preview deposit and try to mint those shares.
        // compare `previewDeposit` with actual minted amounts.

        // 1. Set `supplyFactor`
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rsEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rswEthIonPool)).setSupplyFactor(supplyFactor);

        uint256 firstRoundingError = weEthIonPool.supplyFactor() / RAY + 1;
        uint256 secondRoundingError = rsEthIonPool.supplyFactor() / RAY + 1;
        uint256 thirdRoundingError = rswEthIonPool.supplyFactor() / RAY + 1;
        uint256 roundingError = firstRoundingError + secondRoundingError + thirdRoundingError;

        // 1. Set fee percentage
        feePerc = bound(feePerc, 0, RAY - 1);

        vm.prank(OWNER);
        vault.updateFeePercentage(feePerc);

        // 2. Accrue interest
        daysAccrued = bound(daysAccrued, 1, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        require(vault.caps(weEthIonPool) > 0, "weEthIonPool cap");
        require(vault.caps(rsEthIonPool) > 0, "rsEthIonPool cap");
        require(vault.caps(rswEthIonPool) > 0, "rswEthIonPool cap");

        // 3. Preview deposit
        // - Minimum deposit amount is amount that won't be truncated by zer
        // - amt * RAY / supplyFactor > 0
        uint256 previewDepositAmt = bound(assets, 0, vault.maxDeposit(NULL));
        uint256 expectedShares = vault.previewDeposit(previewDepositAmt);

        console2.log("previewDepositAmt: ", previewDepositAmt);
        console2.log("expectedShares: ", expectedShares);

        deal(address(BASE_ASSET), address(this), previewDepositAmt);
        uint256 resultingShares = vault.deposit(previewDepositAmt, address(this));

        uint256 resultingAssets = vault.previewRedeem(resultingShares);

        uint256 resultingAssetsRoundingError = supplyFactor / RAY + 1;

        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "resulting user asset balance");
        assertEq(
            resultingShares, expectedShares, "resulting shares minted must be equal to shares from preview deposit."
        );
        assertApproxEqAbs(
            resultingAssets,
            previewDepositAmt,
            roundingError,
            "resulting assets must be equal to preview deposit amount"
        );
    }

    function testFuzz_previewMint_MultiplePools(
        uint256 assets,
        uint256 feePerc,
        uint256 daysAccrued,
        uint256 supplyFactor
    )
        public
    {
        // 1. Set `supplyFactor`
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rsEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rswEthIonPool)).setSupplyFactor(supplyFactor);

        uint256 firstRoundingError = weEthIonPool.supplyFactor() / RAY + 1;
        uint256 secondRoundingError = rsEthIonPool.supplyFactor() / RAY + 1;
        uint256 thirdRoundingError = rswEthIonPool.supplyFactor() / RAY + 1;
        uint256 roundingError = firstRoundingError + secondRoundingError + thirdRoundingError;

        // 1. Set fee percentage
        feePerc = bound(feePerc, 0, RAY - 1);

        vm.prank(OWNER);
        vault.updateFeePercentage(feePerc);

        // 2. Accrue interest
        daysAccrued = bound(daysAccrued, 1, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        // 3. Preview mint
        uint256 previewMintAmt = bound(assets, 0, vault.maxMint(NULL));
        console2.log("previewMintAmt: ", previewMintAmt);
        uint256 expectedAssets = vault.previewMint(previewMintAmt);
        console2.log("expectedAssets: ", expectedAssets);

        uint256 prevShares = vault.balanceOf(address(this));

        deal(address(BASE_ASSET), address(this), expectedAssets);

        uint256 prevBalance = BASE_ASSET.balanceOf(address(this));

        uint256 resultingAssets = vault.mint(previewMintAmt, address(this));

        console2.log("resultingAssets: ", resultingAssets);
        console2.log("newBalance: ", BASE_ASSET.balanceOf(address(this)));

        uint256 sharesDiff = vault.balanceOf(address(this)) - prevShares;
        uint256 balanceDiff = prevBalance - BASE_ASSET.balanceOf(address(this));

        uint256 sharesToRedeem = vault.previewWithdraw(expectedAssets);

        // 1. The `previewMintAmt` must be the change in user's shares.
        // 2. The `expectedAssets` from the `previewMint` must be the same as
        // the actual change in user's token balance.
        // 3. The `previewWithdraw` of the `expectedAssets` from `previewMint` must be the same as `previewMintAmt`.

        assertEq(sharesDiff, previewMintAmt, "shares diff must be equal to preview mint amount");
        assertEq(expectedAssets, balanceDiff, "expected assets must be equal to balance diff");
        // assertApproxEqAbs(sharesToRedeem, previewMintAmt, roundingError, "shares to redeem must be equal to preview
        // mint amount");
    }

    /**
     * The edge case of withdraw reverting when withdrawing 1 wei as the last
     * withdraw action does not revert if there are IDLE balances.
     */
    function testFuzz_previewWithdraw_MultiplePools_WithIdleBalance(
        uint256 assets,
        uint256 feePerc,
        uint256 daysAccrued,
        uint256 supplyFactor
    )
        public
    {
        // 1. Set `supplyFactor`
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rsEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rswEthIonPool)).setSupplyFactor(supplyFactor);

        // 1. Set fee percentage
        feePerc = bound(feePerc, 0, RAY - 1);

        vm.prank(OWNER);
        vault.updateFeePercentage(feePerc);

        // 2. Make initial vault deposit
        uint256 initialDeposit = bound(assets, MINIMUM_INITIAL_DEPOSIT, vault.maxDeposit(NULL));
        deal(address(BASE_ASSET), address(this), initialDeposit);
        vault.deposit(initialDeposit, address(this));

        // 3. Accrue interest
        daysAccrued = bound(daysAccrued, 1, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        uint256 previewWithdrawAmt = bound(assets, 0, vault.maxWithdraw(address(this)));
        uint256 expectedShares = vault.previewWithdraw(previewWithdrawAmt);

        uint256 prevBalance = BASE_ASSET.balanceOf(address(this));

        uint256 resultingShares = vault.withdraw(previewWithdrawAmt, address(this), address(this));

        uint256 balanceDiff = BASE_ASSET.balanceOf(address(this)) - prevBalance;

        // 1. Compare the withdrawn assets between the input withdraw assets and
        // real change in token balance.
        // 2. Compare the redeemed shares between `previewWithdraw` and `withdraw`
        assertEq(balanceDiff, previewWithdrawAmt, "balance diff must be equal to preview withdraw amount");
        assertEq(resultingShares, expectedShares, "resulting shares must be equal to expected shares");
    }

    /**
     * The edge case of withdraw reverting when withdrawing 1 wei as the last
     * withdraw action should revert if there are no IDLE balances.
     */
    function testFuzz_previewWithdraw_MultiplePools_WithoutIdleBalance(
        uint256 assets,
        uint256 feePerc,
        uint256 daysAccrued,
        uint256 supplyFactor
    )
        public
    {
        // 1. Set `supplyFactor`
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rsEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rswEthIonPool)).setSupplyFactor(supplyFactor);

        // 1. Set fee percentage
        feePerc = bound(feePerc, 0, RAY - 1);

        vm.prank(OWNER);
        vault.updateFeePercentage(feePerc);

        // 2. Make initial vault deposit
        uint256 initialDeposit = bound(assets, MINIMUM_INITIAL_DEPOSIT, vault.maxDeposit(NULL));
        deal(address(BASE_ASSET), address(this), initialDeposit);
        vault.deposit(initialDeposit, address(this));

        // 3. Empty out the IDLE pool.
        vault.withdraw(BASE_ASSET.balanceOf(address(vault)), address(this), address(this));
        require(BASE_ASSET.balanceOf(address(vault)) == 0, "empty IDLE balance");

        // 3. Accrue interest
        daysAccrued = bound(daysAccrued, 1, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        console2.log("vault.maxWithdraw(address(this)): ", vault.maxWithdraw(address(this)));
        uint256 previewWithdrawAmt = bound(assets, 0, vault.maxWithdraw(address(this)));
        console2.log("previewWithdrawAmt: ", previewWithdrawAmt);
        uint256 expectedShares = vault.previewWithdraw(previewWithdrawAmt);

        uint256 prevBalance = BASE_ASSET.balanceOf(address(this));

        uint256 resultingShares = vault.withdraw(previewWithdrawAmt, address(this), address(this));

        uint256 balanceDiff = BASE_ASSET.balanceOf(address(this)) - prevBalance;

        // 1. Compare the withdrawn assets between the input withdraw assets and
        // real change in token balance.
        // 2. Compare the redeemed shares between `previewWithdraw` and `withdraw`
        assertEq(balanceDiff, previewWithdrawAmt, "balance diff must be equal to preview withdraw amount");
        assertEq(resultingShares, expectedShares, "resulting shares must be equal to expected shares");
    }

    function testFuzz_previewRedeem_MultiplePools(
        uint256 assets,
        uint256 feePerc,
        uint256 daysAccrued,
        uint256 supplyFactor
    )
        public
    {
        // 1. Set `supplyFactor`
        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rsEthIonPool)).setSupplyFactor(supplyFactor);

        supplyFactor = bound(supplyFactor, 1e27, 10e27);
        IonPoolExposed(address(rswEthIonPool)).setSupplyFactor(supplyFactor);

        // 1. Set fee percentage
        feePerc = bound(feePerc, 0, RAY - 1);

        vm.prank(OWNER);
        vault.updateFeePercentage(feePerc);

        // 2. Make initial vault deposit
        uint256 initialDeposit = bound(assets, MINIMUM_INITIAL_DEPOSIT, vault.maxDeposit(NULL));
        deal(address(BASE_ASSET), address(this), initialDeposit);
        vault.deposit(initialDeposit, address(this));

        // 3. Accrue interest
        daysAccrued = bound(daysAccrued, 1, MAX_DAYS);
        vm.warp(block.timestamp + daysAccrued);

        uint256 prevShares = vault.balanceOf(address(this));
        uint256 prevBalance = BASE_ASSET.balanceOf(address(this));

        uint256 previewRedeemAmt = bound(assets, 0, vault.maxRedeem(address(this)));
        uint256 expectedWithdraw = vault.previewRedeem(previewRedeemAmt);

        uint256 resultingWithdraw = vault.redeem(previewRedeemAmt, address(this), address(this));

        uint256 sharesDiff = prevShares - vault.balanceOf(address(this));
        uint256 balanceDiff = BASE_ASSET.balanceOf(address(this)) - prevBalance;

        // 1. Compare the change in shares balance with the `previewRedeemAmt`
        // 2. Compare the resultingWithdrawAmt with the preview expected withdraw amouont.
        assertEq(sharesDiff, previewRedeemAmt, "shares diff must be equal to preview redeem amount");
        assertEq(resultingWithdraw, expectedWithdraw, "resulting withdraw must be equal to expected withdraw");
        assertEq(balanceDiff, resultingWithdraw, "balance diff must be equal to expected withdraw");
    }
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

    // Even though virtual assets and shares makes the attack not 'profitable'
    // for the attacker, the attacker may still be able to cause loss of user
    // funds for a small loss of their own. For example, the attacker may try to
    // cause the user to lose their 1e18 deposit by losing 0.01e18 deposit of
    // their own to grief the user, regardless of economic incentives. If the
    // vault is deployed through a factory that enforces a minimum deposit and a
    // 1e3 shares burn, the attacker should not be able to grief a larger amount
    // than they will lose from their own deposits.
    function testFuzz_InflationAttackTheAttackerLosesMoreThanItCanGrief(uint256 assets) public {
        // Set up factory deployment args with IDLE pool.
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

        VaultFactory factory = new VaultFactory();

        vm.startPrank(deployer);
        BASE_ASSET.approve(address(factory), MIN_INITIAL_DEPOSIT);

        Vault vault = factory.createVault(
            BASE_ASSET,
            FEE_RECIPIENT,
            ZERO_FEES,
            "Ion Vault Token",
            "IVT",
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

        // 1. The vault has not been used.
        // - Initial minimum deposit amt of 1e9 deposited.
        // - 1e3 shares have been locked in factory.
        assertEq(vault.totalSupply(), MIN_INITIAL_DEPOSIT, "initial total supply");
        assertEq(vault.totalAssets(), MIN_INITIAL_DEPOSIT, "initial total assets");
        assertEq(vault.balanceOf(address(factory)), 1e3, "initial factory shares");

        // 2. The attacker makes a first deposit.
        uint256 firstDepositAmt = bound(assets, 1, type(uint128).max);
        setERC20Balance(address(BASE_ASSET), ATTACKER, firstDepositAmt);

        vm.startPrank(ATTACKER);
        BASE_ASSET.approve(address(vault), type(uint256).max);
        vault.mint(firstDepositAmt, ATTACKER);
        vm.stopPrank();

        uint256 attackerClaimAfterMint = vault.previewRedeem(vault.balanceOf(ATTACKER));

        assertEq(BASE_ASSET.balanceOf(ATTACKER), 0, "mint amount equals transfer amount");

        // 3. The attacker donates.
        // - In this case, transfers to vault to increase IDLE deposits.
        // - Check that the attacker loses a portion of the donated funds.
        uint256 donationAmt = bound(assets, firstDepositAmt, type(uint128).max);
        setERC20Balance(address(BASE_ASSET), ATTACKER, donationAmt);

        vm.prank(ATTACKER);
        IERC20(address(BASE_ASSET)).transfer(address(vault), donationAmt);

        uint256 attackerClaimAfterDonation = vault.previewRedeem(vault.balanceOf(ATTACKER));
        uint256 attackerLossFromDonation = donationAmt - (attackerClaimAfterDonation - attackerClaimAfterMint);

        // 4. A user makes a deposit where the shares truncate to zero.
        // - sharesToMint = depositAmt * (newTotalSupply + 1) / (newTotalAssets + 1)
        // - The sharesToMint must be less than 1 to round down to zero
        //     - depositAmt * (newTotalSupply + 1) / (newTotalAssets + 1) < 1
        //     - depositAmt < 1 * (newTotalAssets + 1) / (newTotalSupply + 1)
        uint256 maxDepositAmt = (vault.totalAssets() + 1) / (vault.totalSupply() + 1);
        uint256 userDepositAmt = bound(assets, 1, maxDepositAmt);

        vm.startPrank(USER);
        setERC20Balance(address(BASE_ASSET), USER, userDepositAmt);
        IERC20(address(BASE_ASSET)).approve(address(vault), userDepositAmt);
        vault.deposit(userDepositAmt, USER);
        vm.stopPrank();

        assertEq(vault.balanceOf(USER), 0, "user minted shares must be zero");

        uint256 attackerClaimAfterUser = vault.previewRedeem(vault.balanceOf(ATTACKER));
        uint256 attackerGainFromUser = attackerClaimAfterUser - attackerClaimAfterDonation;

        uint256 attackerNetLoss = firstDepositAmt + donationAmt - attackerClaimAfterUser;
        assertLe(userDepositAmt, attackerNetLoss, "attacker net loss greater than user deposit amt");
    }

    function testFuzz_InflationAttackSmallerDegree() public { }
}
