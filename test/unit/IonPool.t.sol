// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { safeconsole as console } from "forge-std/safeconsole.sol";
import { IonPoolSharedSetup } from "../helpers/IonPoolSharedSetup.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { IonPool } from "../../src/IonPool.sol";
import { RAY } from "../../src/math/RoundedMath.sol";

contract IonPoolTest is IonPoolSharedSetup {
    function test_BasicLendAndWithdraw() external {
        vm.startPrank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);

        assertEq(ionPool.balanceOf(lender1), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(ionPool.totalSupply(), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(lender1), 0);

        uint256 withdrawalAmount = INITIAL_LENDER_UNDERLYING_BALANCE / 2;

        ionPool.withdraw(lender1, withdrawalAmount);

        assertEq(ionPool.balanceOf(lender1), INITIAL_LENDER_UNDERLYING_BALANCE - withdrawalAmount);
        assertEq(ionPool.totalSupply(), INITIAL_LENDER_UNDERLYING_BALANCE - withdrawalAmount);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE - withdrawalAmount);
        assertEq(underlying.balanceOf(lender1), withdrawalAmount);
    }

    function test_BasicBorrowAndRepay() external {
        uint8 stEthIndex = ilkIndexes[address(stEth)];

        vm.startPrank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);

        assertEq(ionPool.balanceOf(lender1), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(ionPool.totalSupply(), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(lender1), 0);

        vm.stopPrank();
        vm.startPrank(borrower1);

        uint256 borrowAmount = 10e18;
        GemJoin stEthJoin = gemJoins[stEthIndex];
        collaterals[stEthIndex].approve(address(stEthJoin), type(uint256).max);
        stEthJoin.join(borrower1, INITIAL_BORROWER_UNDERLYING_BALANCE);

        assertEq(ionPool.gem(stEthIndex, borrower1), INITIAL_BORROWER_UNDERLYING_BALANCE);
        assertEq(stEth.balanceOf(borrower1), 0);
        assertEq(stEth.balanceOf(address(stEthJoin)), INITIAL_BORROWER_UNDERLYING_BALANCE);

        vm.expectRevert(IonPool.CeilingExceeded.selector);
        ionPool.borrow(stEthIndex, debtCeilings[stEthIndex] / RAY + 1); // [RAD] / [RAY] = [WAD]
        ionPool.borrow(stEthIndex, borrowAmount);

        assertEq(ionPool.gem(stEthIndex, borrower1), 0);
        assertEq(underlying.balanceOf(borrower1), borrowAmount);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE - borrowAmount);

        uint256 vaultCollateral = ionPool.collateral(stEthIndex, borrower1);
        uint256 vaultNormalizedDebt = ionPool.normalizedDebt(stEthIndex, borrower1);

        assertEq(vaultCollateral, INITIAL_BORROWER_UNDERLYING_BALANCE);
        assertEq(vaultNormalizedDebt, borrowAmount);
        assertEq(ionPool.totalNormalizedDebt(stEthIndex), borrowAmount);

        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.repay(stEthIndex, borrowAmount);

        assertEq(ionPool.gem(stEthIndex, borrower1), 0);
        assertEq(underlying.balanceOf(borrower1), 0);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);

        vaultCollateral = ionPool.collateral(stEthIndex, borrower1);
        vaultNormalizedDebt = ionPool.normalizedDebt(stEthIndex, borrower1);

        assertEq(vaultCollateral, INITIAL_BORROWER_UNDERLYING_BALANCE);
        assertEq(vaultNormalizedDebt, 0);
        assertEq(ionPool.totalNormalizedDebt(stEthIndex), 0);
    }
}

contract IonPoolTestWithInterestChecks is IonPoolSharedSetup {
    function test_basicLendAndWithdraw() external {
        vm.startPrank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);

        assertEq(ionPool.balanceOf(lender1), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(ionPool.totalSupply(), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(lender1), 0);

        uint256 withdrawalAmount = INITIAL_LENDER_UNDERLYING_BALANCE / 2;

        ionPool.withdraw(lender1, withdrawalAmount);

        assertEq(ionPool.balanceOf(lender1), INITIAL_LENDER_UNDERLYING_BALANCE - withdrawalAmount);
        assertEq(ionPool.totalSupply(), INITIAL_LENDER_UNDERLYING_BALANCE - withdrawalAmount);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE - withdrawalAmount);
        assertEq(underlying.balanceOf(lender1), withdrawalAmount);
    }
}

contract IonPoolTestAdmin { }

contract IonPoolTestPaused { }
