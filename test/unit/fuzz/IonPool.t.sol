// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { WadRayMath, RAY } from "src/libraries/math/WadRayMath.sol";

import { IIonPoolEvents } from "test/helpers/IIonPoolEvents.sol";
import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

uint256 constant COLLATERAL_COUNT = 3;

using WadRayMath for uint256;
using Strings for uint256;

abstract contract IonPool_LenderFuzzTestBase is IonPoolSharedSetup, IIonPoolEvents {
    bool changeSupplyFactor;
    uint256 newSupplyFactor;

    function _changeSupplyFactorIfNeeded() internal prankAgnostic returns (uint256 interestCreated) {
        if (changeSupplyFactor) {
            uint256 totalSupply = ionPool.totalSupply();
            uint256 oldSupplyFactor = ionPool.supplyFactor();
            ionPool.setSupplyFactor(newSupplyFactor);
            interestCreated = totalSupply.rayMulDown(newSupplyFactor - oldSupplyFactor);

            _depositInterestGains(interestCreated);
        }
    }

    function testFuzz_RevertWhen_SupplyingAboveSupplyCap(uint256 supplyAmount) public {
        _changeSupplyFactorIfNeeded();
        vm.assume(supplyAmount < type(uint128).max && supplyAmount > 0);

        uint256 supplyCap = 0;
        ionPool.updateSupplyCap(supplyCap);
        vm.expectRevert(abi.encodeWithSelector(IonPool.DepositSurpassesSupplyCap.selector, supplyAmount, supplyCap));
        ionPool.supply(lender1, supplyAmount, new bytes32[](0));
    }

    function testFuzz_SupplyBase(uint256 supplyAmount) public {
        _changeSupplyFactorIfNeeded();
        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 normalizedAmount = supplyAmount.rayDivDown(currentSupplyFactor);
        vm.assume(supplyAmount < type(uint128).max && normalizedAmount > 0);

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        underlying.mint(lender1, supplyAmount);

        uint256 currentTotalDebt = ionPool.debt();
        (uint256 supplyFactorIncrease,,, uint256 newDebtIncrease,) = _calculateRewardAndDebtDistribution();

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), lender1, supplyAmount);
        vm.expectEmit(true, true, true, true);
        emit Supply(
            lender1,
            lender1,
            supplyAmount,
            currentSupplyFactor + supplyFactorIncrease,
            currentTotalDebt + newDebtIncrease
        );
        vm.prank(lender1);
        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(lender1), normalizedAmount.rayMulDown(currentSupplyFactor));

        uint256 roundingError = currentSupplyFactor / RAY;
        assertLe(ionPool.balanceOf(lender1) - roundingError, supplyAmount);
    }

    function testFuzz_SupplyBaseToDifferentAddress(uint256 supplyAmount) public {
        _changeSupplyFactorIfNeeded();
        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 normalizedAmount = supplyAmount.rayDivDown(currentSupplyFactor);
        vm.assume(supplyAmount < type(uint128).max && normalizedAmount > 0);

        underlying.mint(lender1, supplyAmount);

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        uint256 currentTotalDebt = ionPool.debt();
        (uint256 supplyFactorIncrease,,, uint256 newDebtIncrease,) = _calculateRewardAndDebtDistribution();

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(this), supplyAmount);
        vm.expectEmit(true, true, true, true);
        emit Supply(
            address(this),
            lender1,
            supplyAmount,
            currentSupplyFactor + supplyFactorIncrease,
            currentTotalDebt + newDebtIncrease
        );
        vm.prank(lender1);
        ionPool.supply(address(this), supplyAmount, new bytes32[](0));

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(address(this)), normalizedAmount.rayMulDown(currentSupplyFactor));

        uint256 roundingError = currentSupplyFactor / RAY;
        assertLe(ionPool.balanceOf(address(this)) - roundingError, supplyAmount);
    }

    struct FuzzWithdrawBaseLocs {
        uint256 currentTotalDebt;
        uint256 supplyFactorIncrease;
        uint256 newDebtIncrease;
        uint256 withdrawAmount;
    }

    function testFuzz_WithdrawBase(uint256 supplyAmount, uint256 withdrawAmount) public {
        FuzzWithdrawBaseLocs memory locs;
        locs.withdrawAmount = withdrawAmount;

        vm.assume(supplyAmount < type(uint128).max && supplyAmount > 0);
        underlying.mint(lender1, supplyAmount);

        vm.startPrank(lender1);

        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        // Changing supply factor, means that the interest will be deposited
        _changeSupplyFactorIfNeeded();
        uint256 supplyAmountAfterRebase = ionPool.weth();
        uint256 lender1BalanceAfterRebase = ionPool.balanceOf(lender1);

        assertEq(supplyAmountAfterRebase, lender1BalanceAfterRebase);

        uint256 currentSupplyFactor = ionPool.supplyFactor();
        locs.withdrawAmount = bound(locs.withdrawAmount, 0, supplyAmountAfterRebase);
        vm.assume(locs.withdrawAmount > 0);

        uint256 underlyingBeforeWithdraw = underlying.balanceOf(lender1);
        uint256 rewardAssetBalanceBeforeWithdraw = ionPool.balanceOf(lender1);

        locs.currentTotalDebt = ionPool.debt();
        (locs.supplyFactorIncrease,,, locs.newDebtIncrease,) = _calculateRewardAndDebtDistribution();

        vm.expectEmit(true, true, true, true);
        emit Transfer(lender1, address(0), locs.withdrawAmount);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(
            lender1,
            lender1,
            locs.withdrawAmount,
            currentSupplyFactor + locs.supplyFactorIncrease,
            locs.currentTotalDebt + locs.newDebtIncrease
        );
        ionPool.withdraw(lender1, locs.withdrawAmount);

        uint256 underlyingAfterWithdraw = underlying.balanceOf(lender1);
        uint256 rewardAssetBalanceAfterWithdraw = ionPool.balanceOf(lender1);

        uint256 underlyingWithdrawn = underlyingAfterWithdraw - underlyingBeforeWithdraw;
        uint256 rewardAssetBurned = rewardAssetBalanceBeforeWithdraw - rewardAssetBalanceAfterWithdraw;

        assertEq(ionPool.weth(), supplyAmountAfterRebase - locs.withdrawAmount);
        assertEq(underlyingAfterWithdraw, underlyingBeforeWithdraw + locs.withdrawAmount);
        // Most important invariant
        assertGe(rewardAssetBurned, underlyingWithdrawn);

        uint256 roundingError = currentSupplyFactor / RAY;
        assertLt(ionPool.balanceOf(lender1), lender1BalanceAfterRebase - locs.withdrawAmount + roundingError);
    }

    function testFuzz_WithdrawBaseToDifferentAddress(uint256 supplyAmount, uint256 withdrawAmount) public {
        FuzzWithdrawBaseLocs memory locs;
        locs.withdrawAmount = withdrawAmount;

        vm.assume(supplyAmount < type(uint128).max && supplyAmount > 0);
        underlying.mint(lender1, supplyAmount);

        vm.startPrank(lender1);

        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        // Changing supply factor, means that the interest will be deposited
        _changeSupplyFactorIfNeeded();
        uint256 supplyAmountAfterRebase = ionPool.weth();
        uint256 lender1BalanceAfterRebase = ionPool.balanceOf(lender1);

        assertEq(supplyAmountAfterRebase, lender1BalanceAfterRebase);

        uint256 currentSupplyFactor = ionPool.supplyFactor();
        locs.withdrawAmount = bound(locs.withdrawAmount, 0, supplyAmountAfterRebase);
        vm.assume(locs.withdrawAmount > 0);

        uint256 underlyingBeforeWithdraw = underlying.balanceOf(lender2);
        uint256 rewardAssetBalanceBeforeWithdraw = ionPool.balanceOf(lender1);

        locs.currentTotalDebt = ionPool.debt();
        (locs.supplyFactorIncrease,,, locs.newDebtIncrease,) = _calculateRewardAndDebtDistribution();

        vm.expectEmit(true, true, true, true);
        emit Transfer(lender1, address(0), locs.withdrawAmount);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(
            lender1,
            lender2,
            locs.withdrawAmount,
            currentSupplyFactor + locs.supplyFactorIncrease,
            locs.currentTotalDebt + locs.newDebtIncrease
        );
        ionPool.withdraw(lender2, locs.withdrawAmount);

        uint256 underlyingAfterWithdraw = underlying.balanceOf(lender2);
        uint256 rewardAssetBalanceAfterWithdraw = ionPool.balanceOf(lender1);

        uint256 underlyingWithdrawn = underlyingAfterWithdraw - underlyingBeforeWithdraw;
        uint256 rewardAssetBurned = rewardAssetBalanceBeforeWithdraw - rewardAssetBalanceAfterWithdraw;

        assertEq(ionPool.weth(), supplyAmountAfterRebase - locs.withdrawAmount);
        assertEq(underlyingAfterWithdraw, underlyingBeforeWithdraw + locs.withdrawAmount);
        // Most important invariant
        assertGe(rewardAssetBurned, underlyingWithdrawn);

        uint256 roundingError = currentSupplyFactor / RAY;
        assertLt(ionPool.balanceOf(lender1), lender1BalanceAfterRebase - locs.withdrawAmount + roundingError);
    }
}

abstract contract IonPool_BorrowerFuzzTestBase is IonPoolSharedSetup, IIonPoolEvents {
    bool changeRate;
    uint104[COLLATERAL_COUNT] newRates;

    function _changeRateIfNeeded() internal prankAgnostic {
        if (changeRate) {
            for (uint8 i = 0; i < newRates.length; i++) {
                ionPool.setRate(i, newRates[i]);
            }
        }
    }

    bool warpTime;
    uint256 warpTimeAmount;

    function _warpTimeIfNeeded() internal prankAgnostic {
        if (warpTime) {
            vm.warp(block.timestamp + warpTimeAmount);
        }
    }

    function testFuzz_DepositCollateral(uint256 depositAmount) public {
        vm.assume(depositAmount < type(uint128).max);

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, depositAmount);
            vm.prank(borrower1);
            gemJoins[i].join(borrower1, depositAmount);

            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultCollateralBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, depositAmount);
            assertEq(vaultCollateralBeforeDeposit, 0);

            vm.expectEmit(true, true, true, true);
            emit DepositCollateral(i, borrower1, borrower1, depositAmount);
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultCollateralBeforeDeposit + depositAmount);
        }
    }

    function testFuzz_DepositCollateralToDifferentAddress(uint256 depositAmount) public {
        vm.assume(depositAmount < type(uint128).max);

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, depositAmount);
            vm.prank(borrower1);
            gemJoins[i].join(borrower1, depositAmount);

            uint256 gem1BeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower2);

            assertEq(gem1BeforeDeposit, depositAmount);
            assertEq(vaultBeforeDeposit, 0);

            vm.expectEmit(true, true, true, true);
            emit DepositCollateral(i, borrower2, borrower1, depositAmount);
            vm.prank(borrower1);
            ionPool.depositCollateral({
                ilkIndex: i,
                user: borrower2,
                depositor: borrower1,
                amount: depositAmount,
                proof: new bytes32[](0)
            });

            assertEq(ionPool.gem(i, borrower1), gem1BeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower2), vaultBeforeDeposit + depositAmount);
        }
    }

    function testFuzz_RevertWhen_DepositCollateralFromDifferentAddressWithoutConsent(uint256 depositAmount) public {
        vm.assume(depositAmount < type(uint128).max && depositAmount > 0);

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, depositAmount);
            vm.prank(borrower1);
            gemJoins[i].join(borrower1, depositAmount);

            uint256 gem1BeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower2);

            assertEq(gem1BeforeDeposit, depositAmount);
            assertEq(vaultBeforeDeposit, 0);

            vm.expectRevert(
                abi.encodeWithSelector(IonPool.UseOfCollateralWithoutConsent.selector, i, borrower1, borrower2)
            );
            vm.prank(borrower2);
            ionPool.depositCollateral({
                ilkIndex: i,
                user: borrower2,
                depositor: borrower1,
                amount: depositAmount,
                proof: new bytes32[](0)
            });
        }
    }

    function testFuzz_DepositCollateralFromDifferentAddressWithConsent(uint256 depositAmount) public {
        vm.assume(depositAmount < type(uint128).max);

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, depositAmount);
            vm.prank(borrower1);
            gemJoins[i].join(borrower1, depositAmount);

            uint256 gem1BeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower2);

            assertEq(gem1BeforeDeposit, depositAmount);
            assertEq(vaultBeforeDeposit, 0);

            vm.prank(borrower1);
            ionPool.addOperator(borrower2);

            vm.expectEmit(true, true, true, true);
            emit DepositCollateral(i, borrower2, borrower1, depositAmount);
            vm.prank(borrower2);
            ionPool.depositCollateral({
                ilkIndex: i,
                user: borrower2,
                depositor: borrower1,
                amount: depositAmount,
                proof: new bytes32[](0)
            });

            assertEq(ionPool.gem(i, borrower1), gem1BeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower2), vaultBeforeDeposit + depositAmount);
        }
    }

    function testFuzz_WithdrawCollateral(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount < type(uint128).max);

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, depositAmount);
            vm.prank(borrower1);
            gemJoins[i].join(borrower1, depositAmount);

            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultCollateralBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, depositAmount);
            assertEq(vaultCollateralBeforeDeposit, 0);

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultCollateralBeforeDeposit + depositAmount);

            withdrawAmount = bound(withdrawAmount, 0, depositAmount);

            vm.expectEmit(true, true, true, true);
            emit WithdrawCollateral(i, borrower1, borrower1, withdrawAmount);
            vm.prank(borrower1);
            ionPool.withdrawCollateral(i, borrower1, borrower1, withdrawAmount);

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount + withdrawAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultCollateralBeforeDeposit + depositAmount - withdrawAmount);
        }
    }

    function testFuzz_WithdrawCollateralToDifferentAddress(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount < type(uint128).max);

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, depositAmount);

            vm.prank(borrower1);
            gemJoins[i].join(borrower1, depositAmount);

            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, depositAmount);
            assertEq(vaultBeforeDeposit, 0);

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount);

            withdrawAmount = bound(withdrawAmount, 0, depositAmount);

            vm.expectEmit(true, true, true, true);
            emit WithdrawCollateral(i, borrower1, borrower2, withdrawAmount);
            vm.prank(borrower1);
            ionPool.withdrawCollateral({ ilkIndex: i, user: borrower1, recipient: borrower2, amount: withdrawAmount });

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount - withdrawAmount);
            assertEq(ionPool.gem(i, borrower2), withdrawAmount);
        }
    }

    function testFuzz_RevertWhen_WithdrawCollateralFromDifferentAddressWithoutConsent(
        uint256 depositAmount,
        uint256 withdrawAmount
    )
        public
    {
        vm.assume(depositAmount < type(uint128).max && depositAmount > 0);

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, depositAmount);

            vm.prank(borrower1);
            gemJoins[i].join(borrower1, depositAmount);

            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, depositAmount);
            assertEq(vaultBeforeDeposit, 0);

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount);

            withdrawAmount = bound(withdrawAmount, 1, depositAmount);

            vm.expectRevert(
                abi.encodeWithSelector(IonPool.UnsafePositionChangeWithoutConsent.selector, i, borrower1, borrower2)
            );
            vm.prank(borrower2);
            ionPool.withdrawCollateral({ ilkIndex: i, user: borrower1, recipient: borrower2, amount: withdrawAmount });
        }
    }

    function testFuzz_WithdrawCollateralFromDifferentAddressWithConsent(
        uint256 depositAmount,
        uint256 withdrawAmount
    )
        public
    {
        vm.assume(depositAmount < type(uint128).max);

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, depositAmount);

            vm.prank(borrower1);
            gemJoins[i].join(borrower1, depositAmount);

            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, depositAmount);
            assertEq(vaultBeforeDeposit, 0);

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount);

            withdrawAmount = bound(withdrawAmount, 0, depositAmount);

            vm.prank(borrower1);
            ionPool.addOperator(borrower2);

            vm.expectEmit(true, true, true, true);
            emit WithdrawCollateral(i, borrower1, borrower2, withdrawAmount);
            vm.prank(borrower2);
            ionPool.withdrawCollateral({ ilkIndex: i, user: borrower1, recipient: borrower2, amount: withdrawAmount });

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount - withdrawAmount);
            assertEq(ionPool.gem(i, borrower2), withdrawAmount);
        }
    }

    function testFuzz_Borrow(
        uint256[COLLATERAL_COUNT] memory collateralDepositAmounts,
        uint256 normalizedBorrowAmount
    )
        public
    {
        _changeRateIfNeeded();
        require(COLLATERAL_COUNT == ionPool.ilkCount(), "IonPoolFuzz: Invalid Config");

        uint256 borrowedSoFar;
        for (uint8 i = 0; i < 1; i++) {
            uint256 rate = ionPool.rate(i);

            // This 1:1 ratio is OK since ltv is set at 100%
            uint256 collateralDepositAmount = bound(collateralDepositAmounts[i], 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount * ionPool.spot(i).getSpot() / rate);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 liquidityBefore = ionPool.weth();
            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);

            vm.expectEmit(true, true, true, true);
            emit Borrow(
                i, borrower1, borrower1, normalizedBorrowAmount, rate, ionPool.debt() + normalizedBorrowAmount * rate
            );
            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            borrowedSoFar += liquidityRemoved;

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);
        }
    }

    function testFuzz_BorrowToDifferentAddress(
        uint256[COLLATERAL_COUNT] memory collateralDepositAmounts,
        uint256 normalizedBorrowAmount
    )
        public
    {
        _changeRateIfNeeded();
        require(COLLATERAL_COUNT == ionPool.ilkCount(), "IonPoolFuzz: Invalid Config");

        uint256 borrowedSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 rate = ionPool.rate(i);

            // This 1:1 ratio is OK since ltv is set at 100%
            uint256 collateralDepositAmount = bound(collateralDepositAmounts[i], 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount * ionPool.spot(i).getSpot() / rate);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 liquidityBefore = ionPool.weth();
            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower2), borrowedSoFar);

            vm.expectEmit(true, true, true, true);
            emit Borrow(
                i, borrower1, borrower2, normalizedBorrowAmount, rate, ionPool.debt() + normalizedBorrowAmount * rate
            );
            vm.prank(borrower1);
            ionPool.borrow({
                ilkIndex: i,
                user: borrower1,
                recipient: borrower2,
                amountOfNormalizedDebt: normalizedBorrowAmount,
                proof: new bytes32[](0)
            });

            borrowedSoFar += liquidityRemoved;

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower2), borrowedSoFar);
        }
    }

    function testFuzz_RevertWhen_BorrowFromDifferentAddressWithoutConsent(
        uint256[COLLATERAL_COUNT] memory collateralDepositAmounts,
        uint256 normalizedBorrowAmount
    )
        public
    {
        require(COLLATERAL_COUNT == ionPool.ilkCount(), "IonPoolFuzz: Invalid Config");

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            // This 1:1 ratio is OK since ltv is set at 100%
            uint256 collateralDepositAmount = bound(collateralDepositAmounts[i], 1, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 1, collateralDepositAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower2), 0);

            vm.expectRevert(
                abi.encodeWithSelector(IonPool.UnsafePositionChangeWithoutConsent.selector, i, borrower1, borrower2)
            );
            vm.prank(borrower2);
            ionPool.borrow({
                ilkIndex: i,
                user: borrower1,
                recipient: borrower2,
                amountOfNormalizedDebt: normalizedBorrowAmount,
                proof: new bytes32[](0)
            });
        }
    }

    function testFuzz_BorrowFromDifferentAddressWithConsent(
        uint256[COLLATERAL_COUNT] memory collateralDepositAmounts,
        uint256 normalizedBorrowAmount
    )
        public
    {
        _changeRateIfNeeded();
        require(COLLATERAL_COUNT == ionPool.ilkCount(), "IonPoolFuzz: Invalid Config");

        uint256 borrowedSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 rate = ionPool.rate(i);

            // This 1:1 ratio is OK since ltv is set at 100%
            uint256 collateralDepositAmount = bound(collateralDepositAmounts[i], 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount * ionPool.spot(i).getSpot() / rate);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 liquidityBefore = ionPool.weth();

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);
            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower2), borrowedSoFar);

            vm.prank(borrower1);
            ionPool.addOperator(borrower2);

            vm.expectEmit(true, true, true, true);
            emit Borrow(
                i, borrower1, borrower2, normalizedBorrowAmount, rate, ionPool.debt() + normalizedBorrowAmount * rate
            );
            vm.prank(borrower2);
            ionPool.borrow({
                ilkIndex: i,
                user: borrower1,
                recipient: borrower2,
                amountOfNormalizedDebt: normalizedBorrowAmount,
                proof: new bytes32[](0)
            });

            borrowedSoFar += liquidityRemoved;

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower2), borrowedSoFar);
        }
    }

    function testFuzz_RevertWhen_BorrowBeyondLtv(
        uint256[COLLATERAL_COUNT] memory collateralDepositAmounts,
        uint256 normalizedBorrowAmount
    )
        public
    {
        require(COLLATERAL_COUNT == ionPool.ilkCount(), "IonPoolFuzz: Invalid Config");

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            // This 1:1 ratio is OK since ltv is set at 100%
            uint256 collateralDepositAmount =
                bound(collateralDepositAmounts[i], 0, debtCeilings[i].scaleDownToWad(45) - 1);
            normalizedBorrowAmount =
                bound(normalizedBorrowAmount, collateralDepositAmount + 1, debtCeilings[i].scaleDownToWad(45));

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 spot = ionPool.spot(i).getSpot();
            vm.expectRevert(
                abi.encodeWithSelector(
                    IonPool.UnsafePositionChange.selector, rate * normalizedBorrowAmount, collateralDepositAmount, spot
                )
            );
            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));
        }
    }

    struct RepayLocs {
        uint256 borrowedSoFar;
        uint256 repaidSoFar;
        uint256 fundsCollectedForRepayment;
        uint256 normalizedRepayAmount;
    }

    function testFuzz_Repay(
        uint256 collateralDepositAmount,
        uint256 normalizedBorrowAmount,
        uint256 normalizedRepayAmount
    )
        public
    {
        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);

        RepayLocs memory locs;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            collateralDepositAmount = bound(collateralDepositAmount, 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount);
            locs.normalizedRepayAmount = bound(normalizedRepayAmount, 0, normalizedBorrowAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(
                underlying.balanceOf(borrower1), locs.borrowedSoFar + locs.fundsCollectedForRepayment - locs.repaidSoFar
            );

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);
            locs.borrowedSoFar += liquidityRemoved;

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(
                underlying.balanceOf(borrower1), locs.borrowedSoFar + locs.fundsCollectedForRepayment - locs.repaidSoFar
            );

            _warpTimeIfNeeded();

            (,, uint256 newRateIncrease, uint256 newDebtIncrease,) = ionPool.calculateRewardAndDebtDistribution(i);

            uint256 trueRepayAmount;
            {
                uint256 totalChangeInDebt = (locs.normalizedRepayAmount * (rate + newRateIncrease));
                trueRepayAmount = totalChangeInDebt / RAY;

                // Handle extra dust that might come from repayment
                if (totalChangeInDebt % RAY > 0) ++trueRepayAmount;
                if (trueRepayAmount > underlying.balanceOf(borrower1)) {
                    uint256 interestToPay = trueRepayAmount - underlying.balanceOf(borrower1);
                    locs.fundsCollectedForRepayment += interestToPay;
                    underlying.mint(borrower1, interestToPay);
                }

                vm.expectEmit(true, true, true, true);
                emit Repay(
                    i,
                    borrower1,
                    borrower1,
                    locs.normalizedRepayAmount,
                    rate + newRateIncrease,
                    ionPool.debt() + newDebtIncrease - totalChangeInDebt
                );
                vm.prank(borrower1);
                ionPool.repay(i, borrower1, borrower1, locs.normalizedRepayAmount);
            }

            rate = ionPool.rate(i);

            locs.repaidSoFar += trueRepayAmount;

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount - locs.normalizedRepayAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount - locs.normalizedRepayAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved + trueRepayAmount);
            assertEq(
                underlying.balanceOf(borrower1), locs.borrowedSoFar + locs.fundsCollectedForRepayment - locs.repaidSoFar
            );
        }
    }

    function testFuzz_RepayForDifferentAddress(
        uint256 collateralDepositAmount,
        uint256 normalizedBorrowAmount,
        uint256 normalizedRepayAmount
    )
        public
    {
        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);
        vm.prank(borrower2);
        underlying.approve(address(ionPool), type(uint256).max);

        RepayLocs memory locs;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            collateralDepositAmount = bound(collateralDepositAmount, 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount);
            locs.normalizedRepayAmount = bound(normalizedRepayAmount, 0, normalizedBorrowAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), locs.borrowedSoFar);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);
            locs.borrowedSoFar += liquidityRemoved;

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), locs.borrowedSoFar);

            _warpTimeIfNeeded();

            (,, uint256 newRateIncrease, uint256 newTotalDebt,) = ionPool.calculateRewardAndDebtDistribution(i);

            uint256 trueRepayAmount;
            {
                uint256 totalChangeInDebt = (locs.normalizedRepayAmount * (rate + newRateIncrease));
                trueRepayAmount = totalChangeInDebt / RAY;

                // Handle extra dust that might come from repayment
                if (totalChangeInDebt % RAY > 0) ++trueRepayAmount;

                underlying.mint(borrower2, trueRepayAmount);

                vm.expectEmit(true, true, true, true);
                emit Repay(
                    i,
                    borrower1,
                    borrower2,
                    locs.normalizedRepayAmount,
                    rate + newRateIncrease,
                    ionPool.debt() + newTotalDebt - totalChangeInDebt
                );
                vm.prank(borrower2);
                ionPool.repay({
                    ilkIndex: i,
                    user: borrower1,
                    payer: borrower2,
                    amountOfNormalizedDebt: locs.normalizedRepayAmount
                });
            }

            locs.repaidSoFar += trueRepayAmount;

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount - locs.normalizedRepayAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount - locs.normalizedRepayAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved + trueRepayAmount);
            assertEq(underlying.balanceOf(borrower1), locs.borrowedSoFar);
            assertEq(underlying.balanceOf(borrower2), 0);
        }
    }

    function testFuzz_RevertWhen_RepayFromDifferentAddressWithoutConsent(
        uint256 collateralDepositAmount,
        uint256 normalizedBorrowAmount,
        uint256 normalizedRepayAmount
    )
        public
    {
        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);
        vm.prank(borrower2);
        underlying.approve(address(ionPool), type(uint256).max);

        uint256 borrowedSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            collateralDepositAmount = bound(collateralDepositAmount, 1, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 1, collateralDepositAmount);
            normalizedRepayAmount = bound(normalizedRepayAmount, 1, normalizedBorrowAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            borrowedSoFar += trueBorrowAmount;

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);

            vm.expectRevert(abi.encodeWithSelector(IonPool.TakingWethWithoutConsent.selector, borrower2, borrower1));
            vm.prank(borrower1);
            ionPool.repay({
                ilkIndex: i,
                user: borrower1,
                payer: borrower2,
                amountOfNormalizedDebt: normalizedRepayAmount
            });
        }
    }

    function testFuzz_RepayFromDifferentAddressWithConsent(
        uint256 collateralDepositAmount,
        uint256 normalizedBorrowAmount,
        uint256 normalizedRepayAmount
    )
        public
    {
        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);
        vm.prank(borrower2);
        underlying.approve(address(ionPool), type(uint256).max);

        RepayLocs memory locs;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            collateralDepositAmount = bound(collateralDepositAmount, 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount);
            locs.normalizedRepayAmount = bound(normalizedRepayAmount, 0, normalizedBorrowAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), locs.borrowedSoFar);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);
            locs.borrowedSoFar += liquidityRemoved;

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), locs.borrowedSoFar);

            _warpTimeIfNeeded();

            (,, uint256 newRateIncrease, uint256 newTotalDebt,) = ionPool.calculateRewardAndDebtDistribution(i);

            uint256 trueRepayAmount;
            {
                uint256 totalChangeInDebt = (locs.normalizedRepayAmount * (rate + newRateIncrease));
                trueRepayAmount = totalChangeInDebt / RAY;

                // Handle extra dust that might come from repayment
                if (totalChangeInDebt % RAY > 0) ++trueRepayAmount;

                underlying.mint(borrower2, trueRepayAmount);

                vm.prank(borrower2);
                ionPool.addOperator(borrower1);

                vm.expectEmit(true, true, true, true);
                emit Repay(
                    i,
                    borrower1,
                    borrower2,
                    locs.normalizedRepayAmount,
                    rate + newRateIncrease,
                    ionPool.debt() + newTotalDebt - totalChangeInDebt
                );
                vm.prank(borrower1);
                ionPool.repay({
                    ilkIndex: i,
                    user: borrower1,
                    payer: borrower2,
                    amountOfNormalizedDebt: locs.normalizedRepayAmount
                });
            }

            locs.repaidSoFar += trueRepayAmount;

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount - locs.normalizedRepayAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount - locs.normalizedRepayAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved + trueRepayAmount);
            assertEq(underlying.balanceOf(borrower1), locs.borrowedSoFar);
            assertEq(underlying.balanceOf(borrower2), 0);
        }
    }

    function testFuzz_TransferGem(uint256 collateralDepositAmount, uint256 transferAmount) external {
        vm.assume(collateralDepositAmount < type(uint128).max);
        transferAmount = bound(transferAmount, 0, collateralDepositAmount);

        for (uint8 i = 0; i < collaterals.length; i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.prank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);

            uint256 initialGemBalance = ionPool.gem(i, borrower1);

            vm.expectEmit(true, true, true, true);
            emit TransferGem(i, borrower1, borrower2, transferAmount);
            vm.prank(borrower1);
            ionPool.transferGem(i, borrower1, borrower2, transferAmount);

            assertEq(ionPool.gem(i, borrower1), initialGemBalance - transferAmount);
            assertEq(ionPool.gem(i, borrower2), transferAmount);
        }
    }

    function testFuzz_RevertWhen_TransferGemOnBehalfWithoutConsent(
        uint256 collateralDepositAmount,
        uint256 transferAmount
    )
        external
    {
        vm.assume(collateralDepositAmount < type(uint128).max);
        transferAmount = bound(transferAmount, 0, collateralDepositAmount);

        for (uint8 i = 0; i < collaterals.length; i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.prank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);

            vm.expectRevert(abi.encodeWithSelector(IonPool.GemTransferWithoutConsent.selector, i, borrower1, borrower2));
            vm.prank(borrower2);
            ionPool.transferGem(i, borrower1, borrower2, transferAmount);
        }
    }

    function testFuzz_TransferGemOnBehalfWithConsent(
        uint256 collateralDepositAmount,
        uint256 transferAmount
    )
        external
    {
        vm.assume(collateralDepositAmount < type(uint128).max);
        transferAmount = bound(transferAmount, 0, collateralDepositAmount);

        for (uint8 i = 0; i < collaterals.length; i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.addOperator(borrower2);
            vm.stopPrank();

            uint256 initialGemBalance = ionPool.gem(i, borrower1);

            vm.expectEmit(true, true, true, true);
            emit TransferGem(i, borrower1, borrower2, transferAmount);
            vm.prank(borrower2);
            ionPool.transferGem(i, borrower1, borrower2, transferAmount);

            assertEq(ionPool.gem(i, borrower1), initialGemBalance - transferAmount);
            assertEq(ionPool.gem(i, borrower2), transferAmount);
        }
    }
}

contract IonPool_LenderFuzzTest is IonPool_LenderFuzzTestBase {
    function setUp() public override {
        super.setUp();

        ERC20PresetMinterPauser(_getUnderlying()).mint(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        ERC20PresetMinterPauser(_getUnderlying()).mint(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.prank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);
    }

    function testFuzz_RevertWhen_SupplyingAboveSupplyCap_WithSupplyFactorChange(
        uint256 supplyAmount,
        uint256 _newSupplyFactor
    )
        public
    {
        changeSupplyFactor = true;
        newSupplyFactor = bound(_newSupplyFactor, 1e27, 10e27);
        testFuzz_RevertWhen_SupplyingAboveSupplyCap(supplyAmount);
    }

    function testFuzz_SupplyBase_WithSupplyFactorChange(uint256 supplyAmount, uint256 _newSupplyFactor) public {
        changeSupplyFactor = true;
        newSupplyFactor = bound(_newSupplyFactor, 1e27, 10e27);
        testFuzz_SupplyBase(supplyAmount);
    }

    function testFuzz_SupplyBaseToDifferentAddress_WithSupplyFactorChange(
        uint256 supplyAmount,
        uint256 _newSupplyFactor
    )
        public
    {
        changeSupplyFactor = true;
        newSupplyFactor = bound(_newSupplyFactor, 1e27, 10e27);
        testFuzz_SupplyBaseToDifferentAddress(supplyAmount);
    }

    function testFuzz_WithdrawBase_WithSupplyFactorChange(
        uint256 supplyAmount,
        uint256 withdrawAmount,
        uint256 _newSupplyFactor
    )
        public
    {
        changeSupplyFactor = true;
        newSupplyFactor = bound(_newSupplyFactor, 1e27, 10e27);
        testFuzz_WithdrawBase(supplyAmount, withdrawAmount);
    }

    function testFuzz_WithdrawBaseToDifferentAddress_WithSupplyFactorChange(
        uint256 supplyAmount,
        uint256 withdrawAmount,
        uint256 _newSupplyFactor
    )
        public
    {
        changeSupplyFactor = true;
        newSupplyFactor = bound(_newSupplyFactor, 1e27, 10e27);
        testFuzz_WithdrawBaseToDifferentAddress(supplyAmount, withdrawAmount);
    }
}

contract IonPool_BorrowerFuzzTest is IonPool_BorrowerFuzzTestBase {
    function setUp() public override {
        super.setUp();

        ERC20PresetMinterPauser(_getUnderlying()).mint(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        ERC20PresetMinterPauser(_getUnderlying()).mint(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender2);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender2, INITIAL_LENDER_UNDERLYING_BALANCE, new bytes32[](0));
        vm.stopPrank();

        for (uint256 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            collaterals[i].approve(address(gemJoins[i]), type(uint256).max);
        }
    }

    function test_SetUp() public override {
        super.test_SetUp();

        assertEq(ionPool.weth(), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(ionPool.balanceOf(lender2), INITIAL_LENDER_UNDERLYING_BALANCE);

        for (uint256 i = 0; i < ionPool.ilkCount(); i++) {
            assertEq(collaterals[i].allowance(borrower1, address(gemJoins[i])), type(uint256).max);
        }
    }

    function testFuzz_Borrow_WithRateChange(
        uint256[COLLATERAL_COUNT] memory collateralDepositAmounts,
        uint256 normalizedBorrowAmount,
        uint104[COLLATERAL_COUNT] memory _newRates
    )
        public
    {
        changeRate = true;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            // Disable debt ceiling for this test
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);

            newRates[i] = uint104(bound(_newRates[i], 1e27, 10e27));
        }

        testFuzz_Borrow(collateralDepositAmounts, normalizedBorrowAmount);
    }

    function testFuzz_BorrowToDifferentAddress_WithRateChange(
        uint256[COLLATERAL_COUNT] memory collateralDepositAmounts,
        uint256 normalizedBorrowAmount,
        uint104[COLLATERAL_COUNT] memory _newRates
    )
        public
    {
        changeRate = true;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            // Disable debt ceiling for this test
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);

            newRates[i] = uint104(bound(_newRates[i], 1e27, 10e27));
        }

        testFuzz_BorrowToDifferentAddress(collateralDepositAmounts, normalizedBorrowAmount);
    }

    function testFuzz_BorrowFromDifferentAddressWithConsent_WithRateChange(
        uint256[COLLATERAL_COUNT] memory collateralDepositAmounts,
        uint256 normalizedBorrowAmount,
        uint104[COLLATERAL_COUNT] memory _newRates
    )
        public
    {
        changeRate = true;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            // Disable debt ceiling for this test
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);

            newRates[i] = uint104(bound(_newRates[i], 1e27, 10e27));
        }

        testFuzz_BorrowFromDifferentAddressWithConsent(collateralDepositAmounts, normalizedBorrowAmount);
    }

    function testFuzz_Repay_WithTimeWarp(
        uint256 collateralDepositAmount,
        uint256 normalizedBorrowAmount,
        uint256 normalizedRepayAmount,
        uint256 _warpTimeAmount
    )
        public
    {
        warpTime = true;
        warpTimeAmount = bound(_warpTimeAmount, 100, 10_000);

        testFuzz_Repay(collateralDepositAmount, normalizedBorrowAmount, normalizedRepayAmount);
    }

    function testFuzz_RepayForDifferentAddress_WithTimeWarp(
        uint256 collateralDepositAmount,
        uint256 normalizedBorrowAmount,
        uint256 normalizedRepayAmount,
        uint256 _warpTimeAmount
    )
        public
    {
        warpTime = true;
        warpTimeAmount = bound(_warpTimeAmount, 100, 10_000);

        testFuzz_RepayForDifferentAddress(collateralDepositAmount, normalizedBorrowAmount, normalizedRepayAmount);
    }

    function testFuzz_RepayFromDifferentAddressWithConsent_WithTimeWarp(
        uint256 collateralDepositAmount,
        uint256 normalizedBorrowAmount,
        uint256 normalizedRepayAmount,
        uint256 _warpTimeAmount
    )
        public
    {
        warpTime = true;
        warpTimeAmount = bound(_warpTimeAmount, 100, 10_000);

        testFuzz_RepayFromDifferentAddressWithConsent(
            collateralDepositAmount, normalizedBorrowAmount, normalizedRepayAmount
        );
    }
}
