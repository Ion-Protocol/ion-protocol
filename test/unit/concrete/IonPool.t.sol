// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../src/IonPool.sol";
import { RAY, WadRayMath } from "../../../src/libraries/math/WadRayMath.sol";
import { InterestRate, IlkData } from "../../../src/InterestRate.sol";
import { SpotOracle } from "../../../src/oracles/spot/SpotOracle.sol";
import { Whitelist } from "../../../src/Whitelist.sol";
import { RewardToken } from "../../../src/token/RewardToken.sol";
import { ISpotOracle } from "../../../src/interfaces/ISpotOracle.sol";

import { IIonPoolEvents } from "../../helpers/IIonPoolEvents.sol";
import { IonPoolSharedSetup } from "../../helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "../../helpers/ERC20PresetMinterPauser.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

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

        for (uint256 i = 0; i < lens.ilkCount(iIonPool); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);

            vm.startPrank(borrower1);
            collaterals[i].approve(address(gemJoins[i]), type(uint256).max);
            gemJoins[i].join(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);
            vm.stopPrank();
        }
    }

    function test_SetUp() public override {
        assertEq(lens.liquidity(iIonPool), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(ionPool.balanceOf(lender2), INITIAL_LENDER_UNDERLYING_BALANCE);

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            assertEq(lens.gem(iIonPool, i, borrower1), INITIAL_BORROWER_COLLATERAL_BALANCE);
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

        uint256 supplyAmountBeforeSupply = lens.liquidity(iIonPool);

        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 currentTotalDebt = lens.debt(iIonPool);
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

        assertEq(lens.liquidity(iIonPool), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount);
    }

    function test_SupplyBaseToDifferentAddress() public {
        uint256 supplyAmount = 1e18;

        uint256 supplyAmountBeforeSupply = lens.liquidity(iIonPool);

        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 currentTotalDebt = lens.debt(iIonPool);
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

        assertEq(lens.liquidity(iIonPool), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(address(this)), supplyAmount);
    }

    function test_WithdrawBase() public {
        vm.startPrank(lender1);
        uint256 supplyAmount = 1e18;

        uint256 supplyAmountBeforeSupply = lens.liquidity(iIonPool);

        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        assertEq(lens.liquidity(iIonPool), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount);

        uint256 withdrawAmount = 0.5e18;
        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 currentTotalDebt = lens.debt(iIonPool);
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

        assertEq(lens.liquidity(iIonPool), supplyAmountBeforeSupply + supplyAmount - withdrawAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount - withdrawAmount);
    }

    function test_WithdrawBaseToDifferentAddress() public {
        vm.startPrank(lender1);
        uint256 supplyAmount = 1e18;

        uint256 supplyAmountBeforeSupply = lens.liquidity(iIonPool);

        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        assertEq(lens.liquidity(iIonPool), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount);

        uint256 withdrawAmount = 0.5e18;
        uint256 currentSupplyFactor = ionPool.supplyFactor();
        uint256 currentTotalDebt = lens.debt(iIonPool);
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

        assertEq(lens.liquidity(iIonPool), supplyAmountBeforeSupply + supplyAmount - withdrawAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount - withdrawAmount);
    }

    function test_DepositCollateral() public {
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            uint256 gemBeforeDeposit = lens.gem(iIonPool, i, borrower1);
            uint256 vaultCollateralBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultCollateralBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.expectEmit(true, true, true, true);
            emit DepositCollateral(i, borrower1, borrower1, depositAmount);
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(lens.gem(iIonPool, i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultCollateralBeforeDeposit + depositAmount);
        }
    }

    function test_DepositCollateralToDifferentAddress() public {
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            uint256 gem1BeforeDeposit = lens.gem(iIonPool, i, borrower1);
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

            assertEq(lens.gem(iIonPool, i, borrower1), gem1BeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower2), vaultBeforeDeposit + depositAmount);
        }
    }

    function test_RevertWhen_DepositCollateralFromDifferentAddressWithoutConsent() public {
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            uint256 gem1BeforeDeposit = lens.gem(iIonPool, i, borrower1);
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
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            uint256 gem1BeforeDeposit = lens.gem(iIonPool, i, borrower1);
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

            assertEq(lens.gem(iIonPool, i, borrower1), gem1BeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower2), vaultBeforeDeposit + depositAmount);
        }
    }

    function test_WithdrawCollateral() public {
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            uint256 gemBeforeDeposit = lens.gem(iIonPool, i, borrower1);
            uint256 vaultCollateralBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultCollateralBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(lens.gem(iIonPool, i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultCollateralBeforeDeposit + depositAmount);

            uint256 withdrawAmount = 1e18;

            vm.expectEmit(true, true, true, true);
            emit WithdrawCollateral(i, borrower1, borrower1, withdrawAmount);
            vm.prank(borrower1);
            ionPool.withdrawCollateral(i, borrower1, borrower1, withdrawAmount);

            assertEq(lens.gem(iIonPool, i, borrower1), gemBeforeDeposit - depositAmount + withdrawAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultCollateralBeforeDeposit + depositAmount - withdrawAmount);
        }
    }

    function test_WithdrawCollateralToDifferentAddress() public {
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            uint256 gemBeforeDeposit = lens.gem(iIonPool, i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(lens.gem(iIonPool, i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount);

            uint256 withdrawAmount = 1e18;

            vm.expectEmit(true, true, true, true);
            emit WithdrawCollateral(i, borrower1, borrower2, withdrawAmount);
            vm.prank(borrower1);
            ionPool.withdrawCollateral({ ilkIndex: i, user: borrower1, recipient: borrower2, amount: withdrawAmount });

            assertEq(lens.gem(iIonPool, i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount - withdrawAmount);
            assertEq(lens.gem(iIonPool, i, borrower2), withdrawAmount);
        }
    }

    function test_RevertWhen_WithdrawCollateralFromDifferentAddressWithoutConsent() public {
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            uint256 gemBeforeDeposit = lens.gem(iIonPool, i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(lens.gem(iIonPool, i, borrower1), gemBeforeDeposit - depositAmount);
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
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            uint256 gemBeforeDeposit = lens.gem(iIonPool, i, borrower1);
            uint256 vaultBeforeDeposit = ionPool.collateral(i, borrower1);

            assertEq(gemBeforeDeposit, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(vaultBeforeDeposit, 0);

            uint256 depositAmount = 3e18;

            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, depositAmount, new bytes32[](0));

            assertEq(lens.gem(iIonPool, i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount);

            uint256 withdrawAmount = 1e18;

            vm.prank(borrower1);
            ionPool.addOperator(borrower2);

            vm.expectEmit(true, true, true, true);
            emit WithdrawCollateral(i, borrower1, borrower2, withdrawAmount);
            vm.prank(borrower2);
            ionPool.withdrawCollateral({ ilkIndex: i, user: borrower1, recipient: borrower2, amount: withdrawAmount });

            assertEq(lens.gem(iIonPool, i, borrower1), gemBeforeDeposit - depositAmount);
            assertEq(ionPool.collateral(i, borrower1), vaultBeforeDeposit + depositAmount - withdrawAmount);
            assertEq(lens.gem(iIonPool, i, borrower2), withdrawAmount);
        }
    }

    function test_Borrow() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.expectEmit(true, true, true, true);
            emit Borrow(i, borrower1, borrower1, normalizedBorrowAmount, RAY, RAY * normalizedBorrowAmount * (i + 1));
            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));
        }
    }

    function test_BorrowToDifferentAddress() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

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
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower2), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));
        }
    }

    function test_RevertWhen_BorrowResultsInDustVault() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 0.5e18;

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
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

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
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

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

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
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower2), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));
        }
    }

    function test_RevertWhen_BorrowBeyondLtv() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 11e18;

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), 0);

            uint256 rate = ionPool.rate(i);
            uint256 spot = ISpotOracle(lens.spot(iIonPool, i)).getSpot();
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

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
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
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);
            uint256 trueRepayAmount = normalizedRepayAmount.rayMulUp(rate);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar - repaidSoFar);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            borrowedSoFar += trueBorrowAmount;

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
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
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved + liquidityAdded);
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
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);
            uint256 trueRepayAmount = normalizedRepayAmount.rayMulUp(rate);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            borrowedSoFar += trueBorrowAmount;

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
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
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved + liquidityAdded);
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
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            borrowedSoFar += trueBorrowAmount;

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
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
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);
            uint256 trueRepayAmount = normalizedRepayAmount.rayMulUp(rate);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            borrowedSoFar += trueBorrowAmount;

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
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
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved + liquidityAdded);
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
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

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

            assertEq(lens.debtCeiling(iIonPool, i), newDebtCeiling);
            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
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
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount - normalizedRepayAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved + liquidityAdded);
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
            uint256 initialGemBalance = lens.gem(iIonPool, i, address(this));

            vm.expectEmit(true, true, true, true);
            emit MintAndBurnGem(i, address(this), collateralDepositAmount);
            ionPool.mintAndBurnGem(i, address(this), collateralDepositAmount);

            assertEq(lens.gem(iIonPool, i, address(this)), uint256(int256(initialGemBalance) + collateralDepositAmount));
        }
    }

    function test_TransferGem() external {
        uint256 collateralDepositAmount = 1e18;

        for (uint8 i = 0; i < collaterals.length; i++) {
            uint256 initialGemBalance = lens.gem(iIonPool, i, borrower1);

            vm.expectEmit(true, true, true, true);
            emit TransferGem(i, borrower1, borrower2, collateralDepositAmount);
            vm.prank(borrower1);
            ionPool.transferGem(i, borrower1, borrower2, collateralDepositAmount);

            assertEq(lens.gem(iIonPool, i, borrower1), initialGemBalance - collateralDepositAmount);
            assertEq(lens.gem(iIonPool, i, borrower2), collateralDepositAmount);
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
            uint256 initialGemBalance = lens.gem(iIonPool, i, borrower1);

            vm.prank(borrower1);
            ionPool.addOperator(borrower2);

            vm.expectEmit(true, true, true, true);
            emit TransferGem(i, borrower1, borrower2, collateralDepositAmount);
            vm.prank(borrower2);
            ionPool.transferGem(i, borrower1, borrower2, collateralDepositAmount);

            assertEq(lens.gem(iIonPool, i, borrower1), initialGemBalance - collateralDepositAmount);
            assertEq(lens.gem(iIonPool, i, borrower2), collateralDepositAmount);
        }
    }

    function test_AddOperator() external {
        vm.expectEmit(true, true, true, true);
        emit AddOperator(borrower1, borrower2);
        vm.prank(borrower1);
        ionPool.addOperator(borrower2);

        assertEq(lens.isOperator(iIonPool, borrower1, borrower2), true);
    }

    function test_RemoveOperator() external {
        vm.prank(borrower1);
        ionPool.addOperator(borrower2);

        vm.expectEmit(true, true, true, true);
        emit RemoveOperator(borrower1, borrower2);
        vm.prank(borrower1);
        ionPool.removeOperator(borrower2);

        assertEq(lens.isOperator(iIonPool, borrower1, borrower2), false);
    }
}

contract IonPool_InterestTest is IonPoolSharedSetup, IIonPoolEvents {
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

        for (uint256 i = 0; i < lens.ilkCount(iIonPool); i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);

            vm.startPrank(borrower1);
            collaterals[i].approve(address(gemJoins[i]), type(uint256).max);
            gemJoins[i].join(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);
            vm.stopPrank();
        }
    }

    function test_LastRateUpdatesOnFirstBorrow() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        vm.warp(block.timestamp + 1 days);
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));

            assertEq(lens.lastRateUpdate(iIonPool, i), block.timestamp);
        }
    }

    function test_CalculateRewardAndDebtDistribution() external {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
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

        uint256 supplyFactorBefore = ionPool.supplyFactorUnaccrued();
        uint256[] memory ratesBefore = new uint256[](lens.ilkCount(iIonPool));
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            ratesBefore[i] = lens.rateUnaccrued(iIonPool, i);
        }
        uint256 totalDebtBefore = lens.debtUnaccrued(iIonPool);
        uint256[] memory timestampsBefore = new uint256[](lens.ilkCount(iIonPool));
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            timestampsBefore[i] = lens.lastRateUpdate(iIonPool, i);
        }

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            (uint256 newRateIncrease, uint256 newTimestampIncrease) =
                ionPool.calculateRewardAndDebtDistributionForIlk(i);
            assertEq(rateIncreases[i], newRateIncrease);
            assertEq(timestampIncreases[i], newTimestampIncrease);
        }

        assertEq(supplyFactorBefore + totalSupplyFactorIncrease, ionPool.supplyFactor());
        assertEq(totalDebtBefore + totalDebtIncrease, lens.debt(iIonPool));
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            assertEq(ratesBefore[i] + rateIncreases[i], ionPool.rate(i));
        }

        ionPool.accrueInterest();

        assertEq(ionPool.supplyFactorUnaccrued(), ionPool.supplyFactor());
        assertEq(lens.debtUnaccrued(iIonPool), lens.debt(iIonPool));
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            assertEq(lens.rateUnaccrued(iIonPool, i), ionPool.rate(i));
            assertEq(timestampsBefore[i] + timestampIncreases[i], lens.lastRateUpdate(iIonPool, i));
        }
    }

    // If zero borrow rate, only the last updated timestamp should update
    function test_CalculateRewardAndDebtDistributionZeroBorrowRate() external {
        // update interest rate module to have zero rates.
        IlkData[] memory ilkConfigs = new IlkData[](3);
        uint16[] memory distributionFactors = new uint16[](3);
        distributionFactors[0] = 0.2e4;
        distributionFactors[1] = 0.4e4;
        distributionFactors[2] = 0.4e4;

        for (uint8 i; i != 3; ++i) {
            IlkData memory ilkConfig = IlkData({
                adjustedProfitMargin: 0,
                minimumKinkRate: 0,
                reserveFactor: 0,
                adjustedBaseRate: 0,
                minimumBaseRate: 0,
                optimalUtilizationRate: 9000,
                distributionFactor: distributionFactors[i],
                adjustedAboveKinkSlope: 0,
                minimumAboveKinkSlope: 0
            });
            ilkConfigs[i] = ilkConfig;
        }

        interestRateModule = new InterestRate(ilkConfigs, apyOracle);
        ionPool.updateInterestRateModule(interestRateModule);

        vm.warp(block.timestamp + 1 days);

        (
            uint256 totalSupplyFactorIncrease,
            ,
            uint104[] memory rateIncreases,
            uint256 totalDebtIncrease,
            uint48[] memory timestampIncreases
        ) = ionPool.calculateRewardAndDebtDistribution();

        assertEq(totalSupplyFactorIncrease, 0, "total supply factor");
        assertEq(totalDebtIncrease, 0, "total debt increase");

        for (uint8 i; i != 3; ++i) {
            assertEq(rateIncreases[i], 0, "rate");
            assertEq(timestampIncreases[i], 1 days, "timestamp increase");
        }
    }

    function test_AccrueInterest() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        vm.warp(block.timestamp + 1 days);
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));

            assertEq(lens.lastRateUpdate(iIonPool, i), block.timestamp);
        }
    }

    function test_AccrueInterestForAll() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        uint256 borrowedSoFar;
        uint256[] memory previousRates = new uint256[](lens.ilkCount(iIonPool));
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.expectEmit(true, true, true, true);
            // Rate will be 1e27 here
            emit Borrow(
                i, borrower1, borrower1, normalizedBorrowAmount, RAY, (borrowedSoFar += normalizedBorrowAmount * RAY)
            );
            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));

            previousRates[i] = rate;
        }
    }

    // If distribution factor is zero, should return
    // minimum kink rate.
    function test_DivideByZeroWhenDistributionFactorIsZero() public {
        IlkData[] memory ilkConfigs = new IlkData[](2);
        uint16[] memory distributionFactors = new uint16[](2);
        distributionFactors[0] = 0;
        distributionFactors[1] = 1e4;

        uint96 minimumKinkRate = 4_062_570_058_138_700_000;
        for (uint8 i; i != 2; ++i) {
            IlkData memory ilkConfig = IlkData({
                adjustedProfitMargin: 0,
                minimumKinkRate: minimumKinkRate,
                reserveFactor: 0,
                adjustedBaseRate: 0,
                minimumBaseRate: 0,
                optimalUtilizationRate: 9000,
                distributionFactor: distributionFactors[i],
                adjustedAboveKinkSlope: 0,
                minimumAboveKinkSlope: 0
            });
            ilkConfigs[i] = ilkConfig;
        }

        interestRateModule = new InterestRate(ilkConfigs, apyOracle);

        vm.warp(block.timestamp + 1 days);

        (uint256 zeroDistFactorBorrowRate,) = interestRateModule.calculateInterestRate(0, 10e45, 100e18); // 10%
            // utilization
        assertEq(zeroDistFactorBorrowRate, minimumKinkRate, "borrow rate should be minimum kink rate");

        (uint256 nonZeroDistFactorBorrowRate,) = interestRateModule.calculateInterestRate(1, 100e45, 100e18); // 90%
            // utilization
        assertApproxEqAbs(
            nonZeroDistFactorBorrowRate, minimumKinkRate, 1, "borrow rate at any util should be minimum kink rate"
        );
    }

    // If scaling total eth supply with distribution factor truncates to zero,
    // should return minimum base rate.
    function test_DivideByZeroWhenTotalEthSupplyIsSmall() public {
        IlkData[] memory ilkConfigs = new IlkData[](2);
        uint16[] memory distributionFactors = new uint16[](2);
        distributionFactors[0] = 0.5e4;
        distributionFactors[1] = 0.5e4;

        uint96 minimumKinkRate = 4_062_570_058_138_700_000;
        uint96 minimumBaseRate = 1_580_630_071_273_960_000;
        for (uint8 i; i != 2; ++i) {
            IlkData memory ilkConfig = IlkData({
                adjustedProfitMargin: 0,
                minimumKinkRate: minimumKinkRate,
                reserveFactor: 0,
                adjustedBaseRate: 0,
                minimumBaseRate: minimumBaseRate,
                optimalUtilizationRate: 9000,
                distributionFactor: distributionFactors[i],
                adjustedAboveKinkSlope: 0,
                minimumAboveKinkSlope: 0
            });
            ilkConfigs[i] = ilkConfig;
        }

        interestRateModule = new InterestRate(ilkConfigs, apyOracle);

        vm.warp(block.timestamp + 1 days);

        (uint256 borrowRate,) = interestRateModule.calculateInterestRate(0, 0, 1); // dust amount of eth supply
        assertEq(borrowRate, minimumBaseRate, "borrow rate should be minimum base rate");

        (uint256 borrowRateWithoutTruncation,) = interestRateModule.calculateInterestRate(1, 90e45, 100e18); // 90%
            // utilization
        assertApproxEqAbs(borrowRateWithoutTruncation, minimumKinkRate, 1, "borrow rate without truncation");
    }

    function test_AccrueInterestWhenPaused() public {
        uint256 collateralDepositAmount = 10e18;
        uint256 normalizedBorrowAmount = 5e18;

        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            vm.prank(borrower1);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = lens.liquidity(iIonPool);

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * i);

            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);

            assertEq(ionPool.normalizedDebt(i, borrower1), normalizedBorrowAmount);
            assertEq(lens.totalNormalizedDebt(iIonPool, i), normalizedBorrowAmount);
            assertEq(lens.liquidity(iIonPool), liquidityBefore - liquidityRemoved);
            assertEq(underlying.balanceOf(borrower1), normalizedBorrowAmount.rayMulDown(rate) * (i + 1));
        }

        vm.warp(block.timestamp + 1 hours);

        ionPool.pause();

        uint256 rate0AfterPause = ionPool.rate(0);
        uint256 rate1AfterPause = ionPool.rate(1);
        uint256 rate2AfterPause = ionPool.rate(2);

        uint256 supplyFactorAfterPause = ionPool.supplyFactor();
        uint256 lenderBalanceAfterPause = ionPool.balanceOf(lender2);

        vm.warp(block.timestamp + 365 days);

        (
            uint256 totalSupplyFactorIncrease,
            uint256 treasuryMintAmount,
            uint104[] memory rateIncreases,
            uint256 totalDebtIncrease,
            uint48[] memory timestampIncreases
        ) = ionPool.calculateRewardAndDebtDistribution();

        assertEq(totalSupplyFactorIncrease, 0, "no supply factor increase");
        assertEq(treasuryMintAmount, 0, "no treasury mint amount");
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            assertEq(rateIncreases[i], 0, "no rate increase");
            assertEq(timestampIncreases[i], 365 days, "no timestamp increase");
        }
        assertEq(totalDebtIncrease, 0, "no total debt increase");

        assertEq(ionPool.balanceOf(lender2), lenderBalanceAfterPause, "lender balance doesn't change");
        assertEq(ionPool.supplyFactor(), supplyFactorAfterPause, "supply factor doesn't change");
        assertEq(ionPool.rate(0), rate0AfterPause, "rate 0 doesn't change");
        assertEq(ionPool.rate(1), rate1AfterPause, "rate 1 doesn't change");
        assertEq(ionPool.rate(2), rate2AfterPause, "rate 2 doesn't change");
    }
}

contract IonPool_AdminTest is IonPoolSharedSetup {
    event IlkInitialized(uint8 indexed ilkIndex, address indexed ilkAddress);
    event GlobalDebtCeilingUpdated(uint256 oldCeiling, uint256 newCeiling);
    event InterestRateModuleUpdated(address newModule);
    event WhitelistUpdated(address newWhitelist);

    event IlkSpotUpdated(uint8 indexed ilkIndex, address newSpot);
    event IlkDebtCeilingUpdated(uint8 indexed ilkIndex, uint256 newDebtCeiling);
    event IlkDustUpdated(uint8 indexed ilkIndex, uint256 newDust);

    event AddOperator(address indexed from, address indexed to);
    event RemoveOperator(address indexed from, address indexed to);
    event MintAndBurnGem(uint8 indexed ilkIndex, address indexed usr, int256 wad);
    event TransferGem(uint8 indexed ilkIndex, address indexed src, address indexed dst, uint256 wad);

    event Paused(address account);
    event Unpaused(address account);

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

        uint8 prevIlkCount = uint8(lens.ilkCount(iIonPool));

        vm.expectEmit(true, true, true, true);
        emit IlkInitialized(prevIlkCount, newIlkAddress);
        ionPool.initializeIlk(newIlkAddress);

        assertEq(lens.ilkCount(iIonPool), prevIlkCount + 1);
        assertEq(lens.totalNormalizedDebt(iIonPool, prevIlkCount), 0);
        assertEq(ionPool.rate(prevIlkCount), RAY);
        assertEq(lens.lastRateUpdate(iIonPool, prevIlkCount), block.timestamp);
        assertEq(address(lens.spot(iIonPool, prevIlkCount)), address(0));
        assertEq(lens.debtCeiling(iIonPool, prevIlkCount), 0);
        assertEq(ionPool.dust(prevIlkCount), 0);

        vm.expectRevert(abi.encodeWithSelector(IonPool.IlkAlreadyAdded.selector, newIlkAddress));
        ionPool.initializeIlk(newIlkAddress);

        vm.expectRevert(IonPool.InvalidIlkAddress.selector);
        ionPool.initializeIlk(address(0));
    }

    function test_RevertWhen_Initializing257ThIlk() public {
        uint256 ilkCount = lens.ilkCount(iIonPool);
        // Should lead to 256 total initialized ilks
        for (uint256 i = 0; i < 256 - ilkCount; i++) {
            ionPool.initializeIlk(vm.addr(i + 1));
        }

        vm.expectRevert(IonPool.MaxIlksReached.selector);
        ionPool.initializeIlk(vm.addr(257));
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
            emit IlkSpotUpdated(i, address(newSpotAddress));
            ionPool.updateIlkSpot(i, newSpotAddress);

            assertEq(address(lens.spot(iIonPool, i)), address(newSpotAddress));
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
            emit IlkDebtCeilingUpdated(i, newIlkDebtCeiling);
            ionPool.updateIlkDebtCeiling(i, newIlkDebtCeiling);

            assertEq(lens.debtCeiling(iIonPool, i), newIlkDebtCeiling);
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
            emit IlkDustUpdated(i, newIlkDust);
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

        assertEq(address(lens.interestRateModule(iIonPool)), address(newInterestRateModule));
    }

    function test_UpdateWhitelist() public {
        vm.expectRevert(abi.encodeWithSelector(IonPool.InvalidWhitelist.selector));
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

        assertEq(lens.whitelist(iIonPool), newWhitelist);
    }

    function test_Pause() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.PAUSE_ROLE()
            )
        );
        vm.prank(NON_ADMIN);
        ionPool.pause();

        vm.expectEmit(true, true, true, true);
        emit Paused(address(this));
        ionPool.pause();
        assertEq(ionPool.paused(), true);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.pause();
    }

    function test_Unpause() public {
        vm.expectRevert(PausableUpgradeable.ExpectedPause.selector);
        ionPool.unpause();

        ionPool.pause();
        assertEq(ionPool.paused(), true);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.unpause();

        vm.expectEmit(true, true, true, true);
        emit Unpaused(address(this));
        ionPool.unpause();
        assertEq(ionPool.paused(), false);
    }

    function test_UpdateTreasury() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, NON_ADMIN, ionPool.ION())
        );
        vm.prank(NON_ADMIN);
        ionPool.updateTreasury(address(1));

        vm.expectEmit(true, true, true, true);
        emit TreasuryUpdate(address(1));
        ionPool.updateTreasury(address(1));

        vm.expectRevert(RewardToken.InvalidTreasuryAddress.selector);
        ionPool.updateTreasury(address(0));

        assertEq(ionPool.treasury(), address(1));
    }
}

contract IonPool_PausedTest is IonPoolSharedSetup {
    function test_RevertWhen_CallingFunctionsWhenPaused() public {
        ionPool.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.withdraw(address(0), 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.borrow(0, address(0), address(0), 0, new bytes32[](0));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.withdrawCollateral(0, address(0), address(0), 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.transferGem(0, address(0), address(0), 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.confiscateVault(0, address(0), address(0), address(0), 0, 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.accrueInterest();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.supply(address(0), 0, new bytes32[](0));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.repay(0, address(0), address(0), 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.depositCollateral(0, address(0), address(0), 0, new bytes32[](0));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.repayBadDebt(address(0), 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.withdraw(address(0), 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.borrow(0, address(0), address(0), 0, new bytes32[](0));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.withdrawCollateral(0, address(0), address(0), 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.transferGem(0, address(0), address(0), 0);

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        ionPool.confiscateVault(0, address(0), address(0), address(0), 0, 0);
    }
}

contract IonPool_WhitelistTest is IonPoolSharedSetup {
    address[3] borrowers = [
        0x1111111111111111111111111111111111111111,
        0x2222222222222222222222222222222222222222,
        0x3333333333333333333333333333333333333333
    ];

    address[5] lenders = [
        0x0000000000000000000000000000000000000001,
        0x0000000000000000000000000000000000000002,
        0x0000000000000000000000000000000000000003,
        0x0000000000000000000000000000000000000004,
        0x0000000000000000000000000000000000000005
    ];

    // generate merkle root
    // [["0x1111111111111111111111111111111111111111"],
    // ["0x2222222222222222222222222222222222222222"],
    // ["0x3333333333333333333333333333333333333333"]];
    // => 0xae6afff7b7c4d883d5efd44afa0b98e80317697e8984b4c2de7c54b49c1c4dd4
    bytes32 borrowersRoot = 0xae6afff7b7c4d883d5efd44afa0b98e80317697e8984b4c2de7c54b49c1c4dd4;

    // generate merkle root
    // ["0x0000000000000000000000000000000000000001"],
    // ["0x0000000000000000000000000000000000000002"],
    // ["0x0000000000000000000000000000000000000003"],
    // ["0x0000000000000000000000000000000000000004"],
    // ["0x0000000000000000000000000000000000000005"],
    // => 0x21abd2f655ded75d91fbd5e0b1ad35171a675fd315a077efa7f2d555a26e7094
    bytes32 lendersRoot = 0x21abd2f655ded75d91fbd5e0b1ad35171a675fd315a077efa7f2d555a26e7094;

    bytes[] borrowerProofs = [
        abi.encode(
            32,
            2,
            0x708e7cb9a75ffb24191120fba1c3001faa9078147150c6f2747569edbadee751,
            0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192
        ),
        abi.encode(
            32,
            2,
            0xa7409058568815d08a7ad3c7d4fd44cf1dec90c620cb31e55ad24c654f7ba34f,
            0xbd164a4590db938a0b098da1b25cf37b155f857b38c37c016ad5b8f8fce80192
        ),
        abi.encode(32, 1, 0xc6ce8ae383124b268df66d71f0af2206e6dafb13eba0b03806eed8a4e7991329)
    ];

    bytes[] lenderProofs = [
        abi.encode(
            32,
            2,
            0x2584db4a68aa8b172f70bc04e2e74541617c003374de6eb4b295e823e5beab01,
            0xc949c2dc5da2bd9a4f5ae27532dfbb3551487bed50825cd099ff5d0a8d613ab5
        ),
        abi.encode(
            32,
            3,
            0x16db2e4b9f8dc120de98f8491964203ba76de27b27b29c2d25f85a325cd37477,
            0xc167b0e3c82238f4f2d1a50a8b3a44f96311d77b148c30dc0ef863e1a060dcb6,
            0x1a6dbeb0d179031e5261494ac4b6ee4e284665e8d2ea3ff44f7a2ddf5ca07bb7
        ),
        abi.encode(
            32,
            2,
            0xb5d9d894133a730aa651ef62d26b0ffa846233c74177a591a4a896adfda97d22,
            0xc949c2dc5da2bd9a4f5ae27532dfbb3551487bed50825cd099ff5d0a8d613ab5
        ),
        abi.encode(
            32,
            2,
            0x161691c7185a37ff918e70bebef716ddd87844ac47f419ea23eaf4fe983fbf2c,
            0x1a6dbeb0d179031e5261494ac4b6ee4e284665e8d2ea3ff44f7a2ddf5ca07bb7
        ),
        abi.encode(
            32,
            3,
            0x1ab0c6948a275349ae45a06aad66a8bd65ac18074615d53676c09b67809099e0,
            0xc167b0e3c82238f4f2d1a50a8b3a44f96311d77b148c30dc0ef863e1a060dcb6,
            0x1a6dbeb0d179031e5261494ac4b6ee4e284665e8d2ea3ff44f7a2ddf5ca07bb7
        )
    ];

    Whitelist _whitelist;

    function setUp() public override {
        super.setUp();
        bytes32[] memory borrowersRoots = new bytes32[](3);
        for (uint256 i = 0; i < borrowers.length; ++i) {
            borrowersRoots[i] = borrowersRoot;
        }

        _whitelist = new Whitelist(borrowersRoots, lendersRoot);
        ionPool.updateWhitelist(_whitelist);
    }

    function test_SupplyWorksWhenLenderWhitelisted() external {
        for (uint256 i = 0; i < lenders.length; ++i) {
            uint256 supplyAmount = 1e18;

            underlying.mint(lenders[i], supplyAmount);

            vm.startPrank(lenders[i]);
            underlying.approve(address(ionPool), type(uint256).max);

            bytes32[] memory lenderProof = abi.decode(lenderProofs[i], (bytes32[]));
            ionPool.supply(lenders[i], 1e18, lenderProof);
            vm.stopPrank();
        }
    }

    function test_DepositCollateralWorksWhenBorrowerWhitelisted() external {
        for (uint256 i = 0; i < borrowers.length; ++i) {
            uint256 collateralDepositAmount = 1e18;

            for (uint8 j = 0; j < collaterals.length; ++j) {
                ERC20PresetMinterPauser(address(collaterals[j])).mint(borrowers[i], collateralDepositAmount);

                vm.startPrank(borrowers[i]);
                collaterals[j].approve(address(gemJoins[j]), type(uint256).max);

                gemJoins[j].join(borrowers[i], collateralDepositAmount);

                bytes32[] memory borrowerProof = abi.decode(borrowerProofs[i], (bytes32[]));
                ionPool.depositCollateral(j, borrowers[i], borrowers[i], collateralDepositAmount, borrowerProof);
                vm.stopPrank();
            }
        }
    }

    function test_BorrowWorksWhenBorrowerWhitelisted() external {
        for (uint256 i = 0; i < borrowers.length; ++i) {
            underlying.mint(address(this), 4e18);
            bytes32[] memory lenderProof = abi.decode(lenderProofs[0], (bytes32[]));

            underlying.approve(address(ionPool), type(uint256).max);
            ionPool.supply(lenders[0], 4e18, lenderProof);

            uint256 borrowAmount = 1e18;
            uint256 collateralDepositAmount = 5e18;

            for (uint8 j = 0; j < collaterals.length; ++j) {
                ERC20PresetMinterPauser(address(collaterals[j])).mint(borrowers[i], collateralDepositAmount);

                vm.startPrank(borrowers[i]);
                collaterals[j].approve(address(gemJoins[j]), type(uint256).max);

                gemJoins[j].join(borrowers[i], collateralDepositAmount);

                bytes32[] memory borrowerProof = abi.decode(borrowerProofs[i], (bytes32[]));
                ionPool.depositCollateral(j, borrowers[i], borrowers[i], collateralDepositAmount, borrowerProof);

                ionPool.borrow(j, borrowers[i], borrowers[i], borrowAmount, borrowerProof);
                vm.stopPrank();
            }
        }
    }

    function test_RevertWhen_SupplyingLenderNotWhitelisted() external {
        uint256 supplyAmount = 1e18;

        underlying.mint(lenders[0], supplyAmount);

        underlying.approve(address(ionPool), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedLender.selector, address(this)));
        ionPool.supply(address(this), 1e18, new bytes32[](0));
    }

    function test_SupplyForWhitelistedUser() external {
        uint256 supplyAmount = 1e18;

        underlying.mint(address(this), supplyAmount);

        underlying.approve(address(ionPool), type(uint256).max);

        bytes32[] memory lenderProof = abi.decode(lenderProofs[0], (bytes32[]));
        ionPool.supply(lenders[0], 1e18, lenderProof);
    }

    function test_RevertWhen_DepositingCollateralBorrowerNotWhitelisted() external {
        uint256 collateralDepositAmount = 1e18;

        for (uint8 j = 0; j < collaterals.length; ++j) {
            ERC20PresetMinterPauser(address(collaterals[j])).mint(borrowers[0], collateralDepositAmount);

            vm.startPrank(borrowers[0]);
            collaterals[j].approve(address(gemJoins[j]), type(uint256).max);

            gemJoins[j].join(borrowers[0], collateralDepositAmount);

            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, j, address(this)));
            ionPool.depositCollateral(j, address(this), address(this), collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();
        }
    }

    function test_DepositingCollateralForWhitelistedUser() external {
        uint256 collateralDepositAmount = 1e18;

        for (uint8 j = 0; j < collaterals.length; ++j) {
            ERC20PresetMinterPauser(address(collaterals[j])).mint(address(this), collateralDepositAmount);

            collaterals[j].approve(address(gemJoins[j]), type(uint256).max);

            gemJoins[j].join(address(this), collateralDepositAmount);

            bytes32[] memory borrowerProof = abi.decode(borrowerProofs[0], (bytes32[]));
            ionPool.depositCollateral(j, borrowers[0], address(this), collateralDepositAmount, borrowerProof);
        }
    }

    function test_RevertWhen_BorrowingBorrowerNotWhitelisted() external {
        uint256 borrowAmount = 1e18;

        for (uint8 j = 0; j < collaterals.length; ++j) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, j, address(this)));
            ionPool.borrow(j, address(this), address(this), borrowAmount, new bytes32[](0));
        }
    }

    function test_OperatorCreatesBorrowForWhitelistedUser() external {
        underlying.mint(address(this), 4e18);
        bytes32[] memory lenderProof = abi.decode(lenderProofs[0], (bytes32[]));

        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lenders[0], 4e18, lenderProof);

        uint256 borrowAmount = 1e18;
        uint256 collateralDepositAmount = 5e18;

        for (uint8 j = 0; j < collaterals.length; ++j) {
            ERC20PresetMinterPauser(address(collaterals[j])).mint(borrowers[0], collateralDepositAmount);

            vm.startPrank(borrowers[0]);
            collaterals[j].approve(address(gemJoins[j]), type(uint256).max);

            gemJoins[j].join(borrowers[0], collateralDepositAmount);

            bytes32[] memory borrowerProof = abi.decode(borrowerProofs[0], (bytes32[]));
            ionPool.depositCollateral(j, borrowers[0], borrowers[0], collateralDepositAmount, borrowerProof);

            ionPool.addOperator(address(this));
            vm.stopPrank();

            ionPool.borrow(j, borrowers[0], borrowers[0], borrowAmount, borrowerProof);
        }
    }
}
