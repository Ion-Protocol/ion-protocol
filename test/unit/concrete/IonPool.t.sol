// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { RAY, WadRayMath } from "src/libraries/math/WadRayMath.sol";
import { InterestRate, IlkData } from "src/InterestRate.sol";
import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";
import { IonPausableUpgradeable } from "src/admin/IonPausableUpgradeable.sol";
import { Whitelist } from "src/Whitelist.sol";

import { IIonPoolEvents } from "test/helpers/IIonPoolEvents.sol";
import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

using Strings for uint256;
using WadRayMath for uint256;

contract IonPool_Test is IonPoolSharedSetup, IIonPoolEvents {
    function setUp() public override {
        super.setUp();

        ERC20PresetMinterPauser(_getUnderlying()).mint(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        ERC20PresetMinterPauser(_getUnderlying()).mint(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender2);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender2, INITIAL_LENDER_UNDERLYING_BALANCE, new bytes32[](0));
        vm.stopPrank();

        vm.prank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);

        for (uint256 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);

            vm.startPrank(borrower1);
            collaterals[i].approve(address(gemJoins[i]), type(uint256).max);
            gemJoins[i].join(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);
            vm.stopPrank();
        }
    }

    function test_SetUp() public override {
        assertEq(ionPool.weth(), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(ionPool.balanceOf(lender2), INITIAL_LENDER_UNDERLYING_BALANCE);

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            assertEq(ionPool.gem(i, borrower1), INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(collaterals[i].balanceOf(address(gemJoins[i])), INITIAL_BORROWER_COLLATERAL_BALANCE);
        }
    }

    function test_RevertWhen_SupplyingAboveSupplyCap() public {
        uint256 supplyAmount = 1e18;

        uint256 supplyCap = 0;
        ionPool.updateSupplyCap(supplyCap);

        underlying.mint(address(this), supplyAmount);
        underlying.approve(address(ionPool), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IonPool.DepositSurpassesSupplyCap.selector, supplyAmount, supplyCap));
        ionPool.supply(lender1, supplyAmount, new bytes32[](0));
    }

    function test_SupplyBase() public {
        uint256 supplyAmount = 1e18;

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 currentTotalDebt = ionPool.debt();
        (uint256 supplyFactorIncrease,,, uint256 newDebtIncrease,) = ionPool.calculateRewardAndDebtDistribution();

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
        assertEq(ionPool.balanceOf(lender1), supplyAmount);
    }

    function test_SupplyBaseToDifferentAddress() public {
        uint256 supplyAmount = 1e18;

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 currentTotalDebt = ionPool.debt();
        (uint256 supplyFactorIncrease,,, uint256 newDebtIncrease,) = ionPool.calculateRewardAndDebtDistribution();

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
        assertEq(ionPool.balanceOf(address(this)), supplyAmount);
    }

    function test_WithdrawBase() public {
        vm.startPrank(lender1);
        uint256 supplyAmount = 1e18;

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount);

        uint256 withdrawAmount = 0.5e18;
        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 currentTotalDebt = ionPool.debt();
        (uint256 supplyFactorIncrease,,, uint256 newDebtIncrease,) = ionPool.calculateRewardAndDebtDistribution();

        vm.expectEmit(true, true, true, true);
        emit Transfer(lender1, address(0), withdrawAmount);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(
            lender1,
            lender1,
            withdrawAmount,
            currentSupplyFactor + supplyFactorIncrease,
            currentTotalDebt + newDebtIncrease
        );
        ionPool.withdraw(lender1, withdrawAmount);

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount - withdrawAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount - withdrawAmount);
    }

    function test_WithdrawBaseToDifferentAddress() public {
        vm.startPrank(lender1);
        uint256 supplyAmount = 1e18;

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount);

        uint256 withdrawAmount = 0.5e18;
        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 currentTotalDebt = ionPool.debt();
        (uint256 supplyFactorIncrease,,, uint256 newDebtIncrease,) = ionPool.calculateRewardAndDebtDistribution();

        vm.expectEmit(true, true, true, true);
        emit Transfer(lender1, address(0), withdrawAmount);
        vm.expectEmit(true, true, true, true);
        emit Withdraw(
            lender1,
            address(this),
            withdrawAmount,
            currentSupplyFactor + supplyFactorIncrease,
            currentTotalDebt + newDebtIncrease
        );
        ionPool.withdraw(address(this), withdrawAmount);

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount - withdrawAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount - withdrawAmount);
    }

    function test_DepositCollateral() public {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultCollateralBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultCollateralBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.expectEmit(true, true, true, true);
            emit DepositCollateral(i, borrower1, borrower1, depositAmount);
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultCollateralBeforeDeposit + depositAmount);
        }
    }

    function test_DepositCollateralToDifferentAddress() public {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gem1BeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower2);

            assertEq(gem1BeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

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

    function test_RevertWhen_DepositCollateralFromDifferentAddressWithoutConsent() public {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gem1BeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower2);

            assertEq(gem1BeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

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

    function test_DepositCollateralFromDifferentAddressWithConsent() public {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gem1BeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower2);

            assertEq(gem1BeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

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

    function test_WithdrawCollateral() public {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultCollateralBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultCollateralBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultCollateralBeforeDeposit + depositAmount);

            uint256 withdrawAmount = 1e18;

            vm.expectEmit(true, true, true, true);
            emit WithdrawCollateral(i, borrower1, borrower1, withdrawAmount);
            vm.prank(borrower1);
            ionPool.withdrawCollateral(i, borrower1, borrower1, withdrawAmount);

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount + withdrawAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultCollateralBeforeDeposit + depositAmount - withdrawAmount);
        }
    }

    function test_WithdrawCollateralToDifferentAddress() public {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount);

            uint256 withdrawAmount = 1e18;

            vm.expectEmit(true, true, true, true);
            emit WithdrawCollateral(i, borrower1, borrower2, withdrawAmount);
            vm.prank(borrower1);
            ionPool.withdrawCollateral({ ilkIndex: i, user: borrower1, recipient: borrower2, amount: withdrawAmount });

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount - withdrawAmount);
            assertEq(ionPool.gem(i, borrower2), withdrawAmount);
        }
    }

    function test_RevertWhen_WithdrawCollateralFromDifferentAddressWithoutConsent() public {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount);

            uint256 withdrawAmount = 1e18;
            vm.expectRevert(
                abi.encodeWithSelector(IonPool.UnsafePositionChangeWithoutConsent.selector, i, borrower1, borrower2)
            );
            vm.prank(borrower2);
            ionPool.withdrawCollateral({ ilkIndex: i, user: borrower1, recipient: borrower2, amount: withdrawAmount });
        }
    }

    function test_WithdrawCollateralFromDifferentAddressWithConsent() public {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gemBeforeDeposit = ionPool.gem(i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(ionPool.gem(i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount);

            uint256 withdrawAmount = 1e18;

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

    function test_Borrow() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.expectEmit(true, true, true, true);
            emit Borrow(i, borrower1, borrower1, normalizedBorrowAmount, RAY, RAY * normalizedBorrowAmount * (i + 1));
            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));
        }
    }

    function test_BorrowToDifferentAddress() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower2), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.expectEmit(true, true, true, true);
            emit Borrow(i, borrower1, borrower2, normalizedBorrowAmount, RAY, RAY * normalizedBorrowAmount * (i + 1));
            vm.prank(borrower1);
            ionPool.borrow({
                ilkIndex: i,
                user: borrower1,
                recipient: borrower2,
                amountOfNormalizedDebt: normalizedBorrowAmount,
                proof: new bytes32[](0)
            });

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower2), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));
        }
    }

    function test_RevertWhen_BorrowResultsInDustVault() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 0.5e18;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 dust = 1e45;
            ionPool.updateIlkDust(i, dust);

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), 0);

            uint256 rate = ionPool.rate(i);

            vm.expectRevert(
                abi.encodeWithSelector(IonPool.VaultCannotBeDusty.selector, rate * normalizedBorrowAmount, dust)
            );
            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));
        }
    }

    function test_RevertWhen_BorrowFromDifferentAddressWithoutConsent() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

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

    function test_BorrowFromDifferentAddressWithConsent() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower2), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.prank(borrower1);
            ionPool.addOperator(borrower2);

            vm.expectEmit(true, true, true, true);
            emit Borrow(i, borrower1, borrower2, normalizedBorrowAmount, RAY, RAY * normalizedBorrowAmount * (i + 1));
            vm.prank(borrower2);
            ionPool.borrow({
                ilkIndex: i,
                user: borrower1,
                recipient: borrower2,
                amountOfNormalizedDebt: normalizedBorrowAmount,
                proof: new bytes32[](0)
            });

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower2), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));
        }
    }

    function test_RevertWhen_BorrowBeyondLtv() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 11e18;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), 0);

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

    function test_RevertWhen_BorrowGoesBeyondDebtCeiling() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 debtCeiling = 2e45;
            ionPool.updateIlkDebtCeiling(i, debtCeiling);

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), 0);

            uint256 rate = ionPool.rate(i);

            vm.expectRevert(
                abi.encodeWithSelector(IonPool.CeilingExceeded.selector, rate * normalizedBorrowAmount, debtCeiling)
            );
            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));
        }
    }

    function test_Repay() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;
        uint256 normalizedRepayAmount = 2e18;

        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);

        uint256 borrowedSoFar;
        uint256 repaidSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);
            uint256 trueRepayAmount = normalizedRepayAmount.rayMulUp(rate);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar - repaidSoFar);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            borrowedSoFar += trueBorrowAmount;

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar - repaidSoFar);

            vm.expectEmit(true, true, true, true);
            emit Repay(
                i,
                borrower1,
                borrower1,
                normalizedRepayAmount,
                rate,
                rate * (borrowedSoFar - repaidSoFar - trueRepayAmount)
            );
            vm.prank(borrower1);
            ionPool.repay(i, borrower1, borrower1, normalizedRepayAmount);

            repaidSoFar += trueRepayAmount;

            uint256 liquidityAdded = normalizedRepayAmount.rayMulUp(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved + liquidityAdded);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar - repaidSoFar);
        }
    }

    function test_RepayForDifferentAddress() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;
        uint256 normalizedRepayAmount = 2e18;

        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);
        vm.prank(borrower2);
        underlying.approve(address(ionPool), type(uint256).max);

        underlying.mint(borrower2, 100e18);

        uint256 initialBorrower2Balance = underlying.balanceOf(borrower2);
        uint256 borrowedSoFar;
        uint256 repaidSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);
            uint256 trueRepayAmount = normalizedRepayAmount.rayMulUp(rate);

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

            vm.expectEmit(true, true, true, true);
            emit Repay(
                i,
                borrower1,
                borrower2,
                normalizedRepayAmount,
                rate,
                rate * (borrowedSoFar - repaidSoFar - trueRepayAmount)
            );
            vm.prank(borrower2);
            ionPool.repay({
                ilkIndex: i,
                user: borrower1,
                payer: borrower2,
                amountOfNormalizedDebt: normalizedRepayAmount
            });

            repaidSoFar += trueRepayAmount;

            uint256 liquidityAdded = normalizedRepayAmount.rayMulUp(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved + liquidityAdded);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);
            assertEq(underlying.balanceOf(borrower2), initialBorrower2Balance - repaidSoFar);
        }
    }

    function test_RevertWhen_RepayFromDifferentAddressWithoutConsent() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;
        uint256 normalizedRepayAmount = 2e18;

        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);
        vm.prank(borrower2);
        underlying.approve(address(ionPool), type(uint256).max);

        underlying.mint(borrower2, 100e18);

        uint256 borrowedSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

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

    function test_RepayFromDifferentAddressWithConsent() external {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;
        uint256 normalizedRepayAmount = 2e18;

        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);
        vm.prank(borrower2);
        underlying.approve(address(ionPool), type(uint256).max);

        underlying.mint(borrower2, 100e18);

        uint256 initialBorrower2Balance = underlying.balanceOf(borrower2);
        uint256 borrowedSoFar;
        uint256 repaidSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);
            uint256 trueRepayAmount = normalizedRepayAmount.rayMulUp(rate);

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

            vm.prank(borrower2);
            ionPool.addOperator(borrower1);

            vm.expectEmit(true, true, true, true);
            emit Repay(
                i,
                borrower1,
                borrower2,
                normalizedRepayAmount,
                rate,
                rate * (borrowedSoFar - repaidSoFar - trueRepayAmount)
            );
            vm.prank(borrower1);
            ionPool.repay({
                ilkIndex: i,
                user: borrower1,
                payer: borrower2,
                amountOfNormalizedDebt: normalizedRepayAmount
            });

            repaidSoFar += trueRepayAmount;

            uint256 liquidityAdded = normalizedRepayAmount.rayMulUp(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved + liquidityAdded);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);
            assertEq(underlying.balanceOf(borrower2), initialBorrower2Balance - repaidSoFar);
        }
    }

    struct RepayLocs {
        uint256 borrowedSoFar;
        uint256 repaidSoFar;
        uint256 trueRepayAmount;
        uint256 trueBorrowAmount;
    }

    // This case would take place if borrowing was allowed, then the line was
    // lowered, then the borrower tried to repay but the total debt in the
    // market after the repay is still above the line.
    function test_RepayWhenBorrowsCurrentlyAboveDebtCeilingButRepayDoesNotTakeTotalDebtBelowCeiling() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;
        uint256 normalizedRepayAmount = 1e18;

        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);

        RepayLocs memory locs;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            locs.trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);
            locs.trueRepayAmount = normalizedRepayAmount.rayMulUp(rate);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), locs.borrowedSoFar - locs.repaidSoFar);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            // Update the line
            uint256 newDebtCeiling = 0;
            ionPool.updateIlkDebtCeiling(i, newDebtCeiling);

            locs.borrowedSoFar += locs.trueBorrowAmount;

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.debtCeiling(i), newDebtCeiling);
            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), locs.borrowedSoFar - locs.repaidSoFar);

            vm.expectEmit(true, true, true, true);
            emit Repay(
                i,
                borrower1,
                borrower1,
                normalizedRepayAmount,
                rate,
                rate * (locs.borrowedSoFar - locs.repaidSoFar - locs.trueRepayAmount)
            );
            vm.prank(borrower1);
            ionPool.repay(i, borrower1, borrower1, normalizedRepayAmount);

            locs.repaidSoFar += locs.trueRepayAmount;

            uint256 liquidityAdded = normalizedRepayAmount.rayMulUp(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved + liquidityAdded);
            assertEq(underlying.balanceOf(borrower1), locs.borrowedSoFar - locs.repaidSoFar);
        }
    }

    function test_RevertWhen_MintAndBurnGemWithoutGemJoinRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), ionPool.GEM_JOIN_ROLE()
            )
        );
        ionPool.mintAndBurnGem(0, address(this), 1e18);
    }

    function test_MintAndBurnGem() external {
        ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(this));

        int256 collateralDepositAmount = 1e18;

        for (uint8 i = 0; i < collaterals.length; i++) {
            uint256 initialGemBalance = ionPool.gem(i, address(this));

            vm.expectEmit(true, true, true, true);
            emit MintAndBurnGem(i, address(this), collateralDepositAmount);
            ionPool.mintAndBurnGem(i, address(this), collateralDepositAmount);

            assertEq(ionPool.gem(i, address(this)), uint256(int256(initialGemBalance) + collateralDepositAmount));
        }
    }

    function test_TransferGem() external {
        uint256 collateralDepositAmount = 1e18;

        for (uint8 i = 0; i < collaterals.length; i++) {
            uint256 initialGemBalance = ionPool.gem(i, borrower1);

            vm.expectEmit(true, true, true, true);
            emit TransferGem(i, borrower1, borrower2, collateralDepositAmount);
            vm.prank(borrower1);
            ionPool.transferGem(i, borrower1, borrower2, collateralDepositAmount);

            assertEq(ionPool.gem(i, borrower1), initialGemBalance - collateralDepositAmount);
            assertEq(ionPool.gem(i, borrower2), collateralDepositAmount);
        }
    }

    function test_RevertWhen_TransferGemOnBehalfWithoutConsent() external {
        uint256 collateralDepositAmount = 1e18;

        for (uint8 i = 0; i < collaterals.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(IonPool.GemTransferWithoutConsent.selector, i, borrower1, borrower2));
            vm.prank(borrower2);
            ionPool.transferGem(i, borrower1, borrower2, collateralDepositAmount);
        }
    }

    function test_TransferGemOnBehalfWithConsent() external {
        uint256 collateralDepositAmount = 1e18;

        for (uint8 i = 0; i < collaterals.length; i++) {
            uint256 initialGemBalance = ionPool.gem(i, borrower1);

            vm.prank(borrower1);
            ionPool.addOperator(borrower2);

            vm.expectEmit(true, true, true, true);
            emit TransferGem(i, borrower1, borrower2, collateralDepositAmount);
            vm.prank(borrower2);
            ionPool.transferGem(i, borrower1, borrower2, collateralDepositAmount);

            assertEq(ionPool.gem(i, borrower1), initialGemBalance - collateralDepositAmount);
            assertEq(ionPool.gem(i, borrower2), collateralDepositAmount);
        }
    }

    function test_AddOperator() external {
        vm.expectEmit(true, true, true, true);
        emit AddOperator(borrower1, borrower2);
        vm.prank(borrower1);
        ionPool.addOperator(borrower2);

        assertEq(ionPool.isOperator(borrower1, borrower2), true);
    }

    function test_RemoveOperator() external {
        vm.prank(borrower1);
        ionPool.addOperator(borrower2);

        vm.expectEmit(true, true, true, true);
        emit RemoveOperator(borrower1, borrower2);
        vm.prank(borrower1);
        ionPool.removeOperator(borrower2);

        assertEq(ionPool.isOperator(borrower1, borrower2), false);
    }
}

contract IonPool_InterestTest is IonPoolSharedSetup {
    function setUp() public override {
        super.setUp();

        ERC20PresetMinterPauser(_getUnderlying()).mint(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        ERC20PresetMinterPauser(_getUnderlying()).mint(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender2);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender2, INITIAL_LENDER_UNDERLYING_BALANCE, new bytes32[](0));
        vm.stopPrank();

        vm.prank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);

        for (uint256 i = 0; i < ionPool.ilkCount(); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);

            vm.startPrank(borrower1);
            collaterals[i].approve(address(gemJoins[i]), type(uint256).max);
            gemJoins[i].join(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);
            vm.stopPrank();
        }
    }

    function test_CalculateRewardAndDebtDistribution() external {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
            assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));
        }

        vm.warp(block.timestamp + 1 hours);

        (
            uint256 totalSupplyFactorIncrease,
            ,
            uint104[] memory rateIncreases,
            uint256 totalDebtIncrease,
            uint48[] memory timestampIncreases
        ) = ionPool.calculateRewardAndDebtDistribution();

        uint256 supplyFactorBefore = ionPool.supplyFactor();
        uint256[] memory ratesBefore = new uint256[](ionPool.ilkCount());
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ratesBefore[i] = ionPool.rate(i);
        }
        uint256 totalDebtBefore = ionPool.debt();
        uint256[] memory timestampsBefore = new uint256[](ionPool.ilkCount());
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            timestampsBefore[i] = ionPool.lastRateUpdate(i);
        }

        for (uint8 i = 0; i < 1; i++) {
            (uint256 newRateIncrease, uint256 newTimestampIncrease) =
                ionPool.calculateRewardAndDebtDistributionForIlk(i);
            assertEq(rateIncreases[i], newRateIncrease);
            assertEq(timestampIncreases[i], newTimestampIncrease);
        }

        ionPool.accrueInterest();

        assertEq(supplyFactorBefore + totalSupplyFactorIncrease, ionPool.supplyFactor());
        assertEq(totalDebtBefore + totalDebtIncrease, ionPool.debt());
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            assertEq(ratesBefore[i] + rateIncreases[i], ionPool.rate(i));
            assertEq(timestampsBefore[i] + timestampIncreases[i], ionPool.lastRateUpdate(i));
        }
    }

    // function test_AccrueInterest() public {
    //     uint256 collateralDepositAmount = 10e18;
    //     uint256 normalizedBorrowAmount = 5e18;

    //     uint256[] memory previousRates = new uint256[](ionPool.ilkCount());
    //     for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
    //         vm.prank(borrower1);
    //         ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

    //         uint256 rate = ionPool.rate(i);
    //         uint256 liquidityBefore = ionPool.weth();

    //         assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
    //         assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * i);

    //         vm.expectEmit(true, true, true, true);
    //         emit Borrow(i, borrower1, borrower1, normalizedBorrowAmount, RAY);
    //         vm.prank(borrower1);
    //         ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

    //         uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

    //         assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
    //         assertEq(ionPool.totalNormalizedDebt(i), normalizedBorrowAmount);
    //         assertEq(ionPool.weth(), liquidityBefore - liquidityRemoved);
    //         assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));

    //         previousRates[i] = rate;
    //     }
    // }
}

contract IonPool_AdminTest is IonPoolSharedSetup {
    event IlkInitialized(uint8 indexed ilkIndex, address indexed ilkAddress);
    event GlobalDebtCeilingUpdated(uint256 oldCeiling, uint256 newCeiling);
    event InterestRateModuleUpdated(address newModule);
    event WhitelistUpdated(address newWhitelist);

    event IlkSpotUpdated(address newSpot);
    event IlkDebtCeilingUpdated(uint256 newDebtCeiling);
    event IlkDustUpdated(uint256 newDust);

    event AddOperator(address indexed from, address indexed to);
    event RemoveOperator(address indexed from, address indexed to);
    event MintAndBurnGem(uint8 indexed ilkIndex, address indexed usr, int256 wad);
    event TransferGem(uint8 indexed ilkIndex, address indexed src, address indexed dst, uint256 wad);

    event Paused(IonPausableUpgradeable.Pauses indexed pauseIndex, address account);
    event Unpaused(IonPausableUpgradeable.Pauses indexed pauseIndex, address account);

    event TreasuryUpdate(address treasury);

    // Random non admin address
    address internal immutable NON_ADMIN = vm.addr(33);

    function test_InitializeIlk() public {
        address newIlkAddress = vm.addr(12_451_234);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.initializeIlk(newIlkAddress);

        uint8 prevIlkCount = uint8(ionPool.ilkCount());

        vm.expectEmit(true, true, true, true);
        emit IlkInitialized(prevIlkCount, newIlkAddress);
        ionPool.initializeIlk(newIlkAddress);

        assertEq(ionPool.ilkCount(), prevIlkCount + 1);
        assertEq(ionPool.totalNormalizedDebt(prevIlkCount), 0);
        assertEq(ionPool.rate(prevIlkCount), RAY);
        assertEq(ionPool.lastRateUpdate(prevIlkCount), block.timestamp);
        assertEq(address(ionPool.spot(prevIlkCount)), address(0));
        assertEq(ionPool.debtCeiling(prevIlkCount), 0);
        assertEq(ionPool.dust(prevIlkCount), 0);

        vm.expectRevert(abi.encodeWithSelector(IonPool.IlkAlreadyAdded.selector, newIlkAddress));
        ionPool.initializeIlk(newIlkAddress);

        vm.expectRevert(IonPool.InvalidIlkAddress.selector);
        ionPool.initializeIlk(address(0));
    }

    function test_UpdateIlkSpot() public {
        SpotOracle newSpotAddress = SpotOracle(vm.addr(12_451_234));

        for (uint8 i = 0; i < collaterals.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION()
                )
            );
            vm.prank(NON_ADMIN);
            ionPool.updateIlkSpot(i, newSpotAddress);

            vm.expectEmit(true, true, true, true);
            emit IlkSpotUpdated(address(newSpotAddress));
            ionPool.updateIlkSpot(i, newSpotAddress);

            assertEq(address(ionPool.spot(i)), address(newSpotAddress));
        }
    }

    function test_UpdateIlkDebtCeiling() public {
        uint256 newIlkDebtCeiling = 200e45;

        for (uint8 i = 0; i < collaterals.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION()
                )
            );
            vm.prank(NON_ADMIN);
            ionPool.updateIlkDebtCeiling(i, newIlkDebtCeiling);

            vm.expectEmit(true, true, true, true);
            emit IlkDebtCeilingUpdated(newIlkDebtCeiling);
            ionPool.updateIlkDebtCeiling(i, newIlkDebtCeiling);

            assertEq(ionPool.debtCeiling(i), newIlkDebtCeiling);
        }
    }

    function test_UpdateIlkDust() public {
        uint256 newIlkDust = 2e45;

        for (uint8 i = 0; i < collaterals.length; i++) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION()
                )
            );
            vm.prank(NON_ADMIN);
            ionPool.updateIlkDust(i, newIlkDust);

            vm.expectEmit(true, true, true, true);
            emit IlkDustUpdated(newIlkDust);
            ionPool.updateIlkDust(i, newIlkDust);

            assertEq(ionPool.dust(i), newIlkDust);
        }
    }

    function test_UpdateInterestRateModule() public {
        vm.expectRevert(abi.encodeWithSelector(IonPool.InvalidInterestRateModule.selector, 0));
        ionPool.updateInterestRateModule(InterestRate(address(0)));

        // Random address
        InterestRate newInterestRateModule = InterestRate(address(732));
        // collateralCount will revert with EvmError since the function selector won't exist
        vm.expectRevert();
        ionPool.updateInterestRateModule(newInterestRateModule);

        IlkData[] memory invalidConfig = new IlkData[](2);

        uint16 previousDistributionFactor = ilkConfigs[0].distributionFactor;
        // Distribution factors need to sum to one
        ilkConfigs[0].distributionFactor = 0.6e4;
        for (uint256 i = 0; i < invalidConfig.length; i++) {
            invalidConfig[i] = ilkConfigs[i];
        }

        newInterestRateModule = new InterestRate(invalidConfig, apyOracle);

        vm.expectRevert(abi.encodeWithSelector(IonPool.InvalidInterestRateModule.selector, newInterestRateModule));
        // collateralCount of the interest rate module will be less than the
        // ilkCount in IonPool
        ionPool.updateInterestRateModule(newInterestRateModule);

        ilkConfigs[0].distributionFactor = previousDistributionFactor;
        newInterestRateModule = new InterestRate(ilkConfigs, apyOracle);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.updateInterestRateModule(newInterestRateModule);

        vm.expectEmit(true, true, true, true);
        emit InterestRateModuleUpdated(address(newInterestRateModule));
        ionPool.updateInterestRateModule(newInterestRateModule);

        assertEq(address(ionPool.interestRateModule()), address(newInterestRateModule));
    }

    function test_UpdateWhitelist() public {
        vm.expectRevert(abi.encodeWithSelector(IonPool.InvalidWhitelist.selector, 0));
        ionPool.updateWhitelist(Whitelist(address(0)));

        // Random address
        address newWhitelist = address(732);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.updateWhitelist(Whitelist(newWhitelist));

        vm.expectEmit(true, true, true, true);
        emit WhitelistUpdated(newWhitelist);
        ionPool.updateWhitelist(Whitelist(newWhitelist));

        assertEq(ionPool.whitelist(), newWhitelist);
    }

    function test_PauseUnsafeActions() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.pauseUnsafeActions();

        vm.expectEmit(true, true, true, true);
        emit Paused(IonPausableUpgradeable.Pauses.UNSAFE, address(this));
        ionPool.pauseUnsafeActions();
        assertEq(ionPool.paused(IonPausableUpgradeable.Pauses.UNSAFE), true);

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.pauseUnsafeActions();
    }

    function test_UnpauseUnsafeActions() public {
        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.ExpectedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.unpauseUnsafeActions();

        ionPool.pauseUnsafeActions();
        assertEq(ionPool.paused(IonPausableUpgradeable.Pauses.UNSAFE), true);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.unpauseUnsafeActions();

        vm.expectEmit(true, true, true, true);
        emit Unpaused(IonPausableUpgradeable.Pauses.UNSAFE, address(this));
        ionPool.unpauseUnsafeActions();
        assertEq(ionPool.paused(IonPausableUpgradeable.Pauses.UNSAFE), false);
    }

    function test_PauseSafeActions() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.pauseSafeActions();

        vm.expectEmit(true, true, true, true);
        emit Paused(IonPausableUpgradeable.Pauses.SAFE, address(this));
        ionPool.pauseSafeActions();
        assertEq(ionPool.paused(IonPausableUpgradeable.Pauses.SAFE), true);

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE)
        );
        ionPool.pauseSafeActions();
    }

    function test_UnpauseSafeActions() public {
        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.ExpectedPause.selector, IonPausableUpgradeable.Pauses.SAFE)
        );
        ionPool.unpauseSafeActions();

        ionPool.pauseSafeActions();
        assertEq(ionPool.paused(IonPausableUpgradeable.Pauses.SAFE), true);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.unpauseSafeActions();

        vm.expectEmit(true, true, true, true);
        emit Unpaused(IonPausableUpgradeable.Pauses.SAFE, address(this));
        ionPool.unpauseSafeActions();
        assertEq(ionPool.paused(IonPausableUpgradeable.Pauses.SAFE), false);
    }

    function test_UpdateTreasury() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.updateTreasury(address(0));

        vm.expectEmit(true, true, true, true);
        emit TreasuryUpdate(address(0));
        ionPool.updateTreasury(address(0));

        assertEq(ionPool.treasury(), address(0));
    }
}

contract IonPool_PausedTest is IonPoolSharedSetup {
    function test_RevertWhen_CallingUnsafeFunctionsWhenPausedUnsafe() public {
        ionPool.pauseUnsafeActions();

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.withdraw(address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.borrow(0, address(0), address(0), 0, new bytes32[](0));

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.withdrawCollateral(0, address(0), address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.transferGem(0, address(0), address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.confiscateVault(0, address(0), address(0), address(0), 0, 0);
    }

    function test_RevertWhen_CallingSafeFunctionsWhenPausedSafe() public {
        ionPool.pauseSafeActions();

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE)
        );
        ionPool.accrueInterest();

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE)
        );
        ionPool.supply(address(0), 0, new bytes32[](0));

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE)
        );
        ionPool.repay(0, address(0), address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE)
        );
        ionPool.depositCollateral(0, address(0), address(0), 0, new bytes32[](0));

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE)
        );
        ionPool.repayBadDebt(address(0), 0);
    }

    function test_RevertWhen_CallingUnsafeFunctionsWhenPausedSafe() public {
        ionPool.pauseSafeActions();

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.withdraw(address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.borrow(0, address(0), address(0), 0, new bytes32[](0));

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.withdrawCollateral(0, address(0), address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.transferGem(0, address(0), address(0), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE)
        );
        ionPool.confiscateVault(0, address(0), address(0), address(0), 0, 0);
    }
}
