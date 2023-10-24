// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GemJoin } from "src/join/GemJoin.sol";
import { IonPool } from "src/IonPool.sol";
import { WAD, RAY, RAD, RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { InterestRate, IlkData } from "src/InterestRate.sol";

import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";
import { console2 } from "forge-std/console2.sol";

using Strings for uint256;
using RoundedMath for uint256;

contract IonPool_BasicUnitTest is IonPoolSharedSetup {

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
        // uint8 stEthIndex = ionPool.getIlkIndex(address(stEth));

        // vm.startPrank(lender1);
        // underlying.approve(address(ionPool), type(uint256).max);
        // ionPool.supply(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);

        // assertEq(ionPool.balanceOf(lender1), INITIAL_LENDER_UNDERLYING_BALANCE);
        // assertEq(ionPool.totalSupply(), INITIAL_LENDER_UNDERLYING_BALANCE);
        // assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);
        // assertEq(underlying.balanceOf(lender1), 0);

        // vm.stopPrank();
        // vm.startPrank(borrower1);

        // uint256 borrowAmount = 10e18;
        // GemJoin stEthJoin = gemJoins[stEthIndex];
        // collaterals[stEthIndex].approve(address(stEthJoin), type(uint256).max);
        // stEthJoin.join(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);

        // assertEq(ionPool.gem(stEthIndex, borrower1), INITIAL_BORROWER_COLLATERAL_BALANCE);
        // assertEq(stEth.balanceOf(borrower1), 0);
        // assertEq(stEth.balanceOf(address(stEthJoin)), INITIAL_BORROWER_COLLATERAL_BALANCE);

        // vm.expectRevert(IonPool.CeilingExceeded.selector);
        // _borrowHelper(stEthIndex, borrower1, int256(debtCeilings[stEthIndex] / RAY + 1)); // [RAD] / [RAY] = [WAD]
        // ionHandler.borrow(stEthIndex, borrowAmount);

        // assertEq(ionPool.gem(stEthIndex, borrower1), 0);
        // assertEq(underlying.balanceOf(borrower1), borrowAmount);
        // assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE - borrowAmount);

        // uint256 vaultCollateral = ionPool.collateral(stEthIndex, borrower1);
        // uint256 vaultNormalizedDebt = ionPool.normalizedDebt(stEthIndex, borrower1);

        // assertEq(vaultCollateral, INITIAL_BORROWER_COLLATERAL_BALANCE);
        // assertEq(vaultNormalizedDebt, borrowAmount);
        // assertEq(ionPool.totalNormalizedDebt(stEthIndex), borrowAmount);

        // underlying.approve(address(ionHandler), type(uint256).max);
        // ionHandler.repay(stEthIndex, borrowAmount);

        // assertEq(ionPool.gem(stEthIndex, borrower1), 0);
        // assertEq(underlying.balanceOf(borrower1), 0);
        // assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);

        // vaultCollateral = ionPool.collateral(stEthIndex, borrower1);
        // vaultNormalizedDebt = ionPool.normalizedDebt(stEthIndex, borrower1);

        // assertEq(vaultCollateral, INITIAL_BORROWER_COLLATERAL_BALANCE);
        // assertEq(vaultNormalizedDebt, 0);
        // assertEq(ionPool.totalNormalizedDebt(stEthIndex), 0);
    }
}

contract IonPool_ModifyPositionTest is IonPoolSharedSetup {
    // --- Events ---
    event Init(uint8 indexed ilkIndex, address indexed ilkAddress);
    event GlobalDebtCeilingUpdated(uint256 oldCeiling, uint256 newCeiling);
    event InterestRateModuleUpdated(address oldModule, address newModule);
    event Hope(address indexed from, address indexed to);
    event Nope(address indexed from, address indexed to);
    event MintAndBurnGem(uint8 indexed ilkIndex, address indexed usr, int256 wad);
    event TransferGem(uint8 indexed ilkIndex, address indexed src, address indexed dst, uint256 wad);
    event Move(address indexed src, address indexed dst, uint256 rad);
    event ModifyPosition(
        uint8 indexed ilkIndex,
        address indexed u,
        address v,
        address w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    );

    function setUp() public override {
        super.setUp();

        vm.startPrank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        vm.stopPrank();

        vm.startPrank(lender2);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);
        vm.stopPrank();

        for (uint8 i = 0; i < collaterals.length; i++) {
            // GemJoin joinContract = gemJoins[i];

            // ionPool.updateIlkDebtCeiling(i, debtCeilings[i]);

            // vm.startPrank(borrower1);
            // collaterals[i].approve(address(joinContract), type(uint256).max);
            // joinContract.joinAndDepositInVault(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);
            // vm.stopPrank();

            // vm.startPrank(borrower2);
            // collaterals[i].approve(address(joinContract), type(uint256).max);
            // joinContract.joinAndDepositInVault(borrower2, INITIAL_BORROWER_COLLATERAL_BALANCE);
            // vm.stopPrank();
        }

        // Necessary for paying back debt
        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);
        vm.prank(borrower2);
        underlying.approve(address(ionPool), type(uint256).max);
    }

    function test_setUp() public override {
        for (uint8 i = 0; i < collaterals.length; i++) {
            (uint256 collateral1) = ionPool.collateral(i, borrower1);
            (uint256 normalizedDebt1) = ionPool.normalizedDebt(i, borrower1);
            (uint256 collateral2) = ionPool.collateral(i, borrower2);
            (uint256 normalizedDebt2) = ionPool.normalizedDebt(i, borrower2);

            assertEq(collateral1, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(collateral2, INITIAL_BORROWER_COLLATERAL_BALANCE);
            assertEq(normalizedDebt1, 0);
            assertEq(normalizedDebt2, 0);

            uint256 borrower1Gem = ionPool.gem(i, borrower1);
            uint256 borrower2Gem = ionPool.gem(i, borrower2);

            assertEq(borrower1Gem, 0);
            assertEq(borrower2Gem, 0);
        }

        assertEq(ionPool.debt(), 0);
    }

    function test_modifyPositionMint() public {
        uint8 stEthIndex = ionPool.getIlkIndex(address(wstEth));

        int256 collateralToDeposit = 0;
        // rate accumulator is 1 at this point
        int256 normalizedDebt = 10;
        uint256 normalizedDebtWad = uint256(normalizedDebt) * WAD;

        (uint256 borrowRateBefore,) = ionPool.getCurrentBorrowRate(stEthIndex);

        vm.expectEmit(true, true, true, true);
        ionPool.borrow(stEthIndex, borrower1, borrower1, normalizedDebtWad);

        (uint256 borrowRateAfter,) = ionPool.getCurrentBorrowRate(stEthIndex);

        // Taking out debt should increase the borrow rate
        assertGt(borrowRateAfter, borrowRateBefore);

        assertEq(underlying.balanceOf(borrower1), uint256(normalizedDebtWad));
        assertEq(ionPool.collateral(stEthIndex, borrower1), INITIAL_BORROWER_COLLATERAL_BALANCE);
        assertEq(ionPool.normalizedDebt(stEthIndex, borrower1), uint256(normalizedDebtWad));
        assertEq(ionPool.gem(stEthIndex, borrower1), 0);
        assertEq(ionPool.totalNormalizedDebt(stEthIndex), uint256(normalizedDebtWad));
    }

    function test_modifyPositionRepay() public {
        uint8 stEthIndex = ionPool.getIlkIndex(address(wstEth));

        int256 collateralToDeposit = 0;
        // rate accumulator is 1 at this point
        int256 debt = 10;
        uint256 debtWad = uint256(debt) * WAD;

        uint256 initialLiquidity = underlying.balanceOf(address(ionPool));

        ionPool.borrow(stEthIndex, borrower1, borrower1, debtWad);

        (uint256 borrowRateBefore,) = ionPool.getCurrentBorrowRate(stEthIndex);
        uint256 borrower1DebtBefore = ionPool.rate(stEthIndex) * ionPool.normalizedDebt(stEthIndex, borrower1); // [RAD]
        uint256 totalDebtBefore = ionPool.rate(stEthIndex) * ionPool.totalNormalizedDebt(stEthIndex);

        vm.warp(block.timestamp + 100);

        (,, uint256 incomingRate,) = ionPool.calculateRewardAndDebtDistribution(stEthIndex);
        uint256 originalDebtNormalized = ionPool.normalizedDebt(stEthIndex, borrower1).rayDivDown(incomingRate);

        vm.expectEmit(true, true, true, true);
        emit ModifyPosition(
            stEthIndex, borrower1, borrower1, borrower1, collateralToDeposit, -int256(originalDebtNormalized)
        );
        ionPool.repay(stEthIndex, borrower1, borrower1, originalDebtNormalized);

        (uint256 borrowRateAfter,) = ionPool.getCurrentBorrowRate(stEthIndex);
        uint256 borrower1DebtAfter = ionPool.rate(stEthIndex) * ionPool.normalizedDebt(stEthIndex, borrower1); // [RAD]
        uint256 totalDebtAfter = ionPool.rate(stEthIndex) * ionPool.totalNormalizedDebt(stEthIndex);

        // Borrow rate should decrease after a repayment
        assertLt(borrowRateAfter, borrowRateBefore);
        // Since time has passed, even though borrower paid back everything they
        // borrowed. They should still have interest payments
        console.log(borrower1DebtAfter);
        assertGt(borrower1DebtAfter, 0);
        assertGt(totalDebtAfter, 0);

        // borrower1DebtAfter < borrower1DebtBefore
        assertLt(borrower1DebtAfter, borrower1DebtBefore);
        // totalDebtAfter < totalDebtBefore
        assertLt(totalDebtAfter, totalDebtBefore);

        assertEq(underlying.balanceOf(address(ionPool)), initialLiquidity);
        // All collateral was initially deposited straight into vault, and never moved
        assertEq(ionPool.collateral(stEthIndex, borrower1), INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    // function test_modifyPositionClearAllDebtAfterInterestAccrues() public {

    // }

    // function testModifyPositionCannotExceedIlkCeiling() public {
    //     vat.file(ILK, "line", 10 * RAD);

    //     vm.expectRevert("Vat/ceiling-exceeded");
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, int256(100 * WAD), int256(100 * WAD));
    // }

    // function testModifyPositionCannotExceedGlobalCeiling() public {
    //     vat.file("Line", 10 * RAD);

    //     vm.expectRevert("Vat/ceiling-exceeded");
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, int256(100 * WAD), int256(100 * WAD));
    // }

    // function testModifyPositionNotSafe() public {
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, int256(100 * WAD), int256(100 * WAD));

    //     assertEq(usr1.dai(), 100 * RAD);
    //     assertEq(usr1.ink(ILK), 100 * WAD);
    //     assertEq(usr1.art(ILK), 100 * WAD);
    //     assertEq(usr1.gems(ILK), 0);

    //     // Cannot mint one more DAI it's undercollateralized
    //     vm.expectRevert("Vat/not-safe");
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, 0, int256(1 * WAD));

    //     // Cannot remove even one ink or it's undercollateralized
    //     vm.expectRevert("Vat/not-safe");
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, -int256(1 * WAD), 0);
    // }

    // function testModifyPositionNotSafeLessRisky() public {
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, int256(50 * WAD), int256(50 * WAD));

    //     assertEq(usr1.dai(), 50 * RAD);
    //     assertEq(usr1.ink(ILK), 50 * WAD);
    //     assertEq(usr1.art(ILK), 50 * WAD);
    //     assertEq(usr1.gems(ILK), 50 * WAD);

    //     vat.file(ILK, "spot", RAY / 2);     // Vault is underwater

    //     // Can repay debt even if it's undercollateralized
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, 0, -int256(1 * WAD));

    //     assertEq(usr1.dai(), 49 * RAD);
    //     assertEq(usr1.ink(ILK), 50 * WAD);
    //     assertEq(usr1.art(ILK), 49 * WAD);
    //     assertEq(usr1.gems(ILK), 50 * WAD);

    //     // Can add gems even if it's undercollateralized
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, int256(1 * WAD), 0);

    //     assertEq(usr1.dai(), 49 * RAD);
    //     assertEq(usr1.ink(ILK), 51 * WAD);
    //     assertEq(usr1.art(ILK), 49 * WAD);
    //     assertEq(usr1.gems(ILK), 49 * WAD);
    // }

    // function testModifyPositionPermissionlessAddCollateral() public {
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, int256(100 * WAD), int256(100 * WAD));

    //     assertEq(usr1.dai(), 100 * RAD);
    //     assertEq(usr1.ink(ILK), 100 * WAD);
    //     assertEq(usr1.art(ILK), 100 * WAD);
    //     assertEq(usr1.gems(ILK), 0);
    //     assertEq(usr2.gems(ILK), 100 * WAD);

    //     vm.expectEmit(true, true, true, true);
    //     emit ModifyPosition(ILK, ausr1, ausr2, TEST_ADDRESS, int256(100 * WAD), 0);
    //     usr2.frob(ILK, ausr1, ausr2, TEST_ADDRESS, int256(100 * WAD), 0);

    //     assertEq(usr1.dai(), 100 * RAD);
    //     assertEq(usr1.ink(ILK), 200 * WAD);
    //     assertEq(usr1.art(ILK), 100 * WAD);
    //     assertEq(usr1.gems(ILK), 0);
    //     assertEq(usr2.gems(ILK), 0);
    // }

    // function testModifyPositionPermissionlessRepay() public {
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, int256(100 * WAD), int256(100 * WAD));
    //     vat.suck(TEST_ADDRESS, ausr2, 100 * RAD);

    //     assertEq(usr1.dai(), 100 * RAD);
    //     assertEq(usr1.ink(ILK), 100 * WAD);
    //     assertEq(usr1.art(ILK), 100 * WAD);
    //     assertEq(usr1.gems(ILK), 0);
    //     assertEq(usr2.dai(), 100 * RAD);

    //     vm.expectEmit(true, true, true, true);
    //     emit ModifyPosition(ILK, ausr1, TEST_ADDRESS, ausr2, 0, -int256(100 * WAD));
    //     usr2.frob(ILK, ausr1, TEST_ADDRESS, ausr2, 0, -int256(100 * WAD));

    //     assertEq(usr1.dai(), 100 * RAD);
    //     assertEq(usr1.ink(ILK), 100 * WAD);
    //     assertEq(usr1.art(ILK), 0);
    //     assertEq(usr1.gems(ILK), 0);
    //     assertEq(usr2.dai(), 0);
    // }

    // function testModifyPositionDusty() public {
    //     vm.expectRevert("Vat/dust");
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, int256(9 * WAD), int256(9 * WAD));
    // }

    // function testModifyPositionOther() public {
    //     // usr2 can completely manipulate usr1's vault with permission
    //     usr1.hope(ausr2);
    //     usr2.frob(ILK, ausr1, ausr1, ausr1, int256(100 * WAD), int256(100 * WAD));
    //     usr2.frob(ILK, ausr1, ausr1, ausr1, -int256(50 * WAD), -int256(50 * WAD));
    // }

    // function testModifyPositionNonOneRate() public {
    //     vat.fold(ILK, TEST_ADDRESS, int256(1 * RAY / 10));  // 10% interest collected

    //     assertEq(usr1.dai(), 0);
    //     assertEq(usr1.ink(ILK), 0);
    //     assertEq(usr1.art(ILK), 0);
    //     assertEq(usr1.gems(ILK), 100 * WAD);
    //     assertEq(vat.Art(ILK), 0);

    //     vm.expectEmit(true, true, true, true);
    //     emit ModifyPosition(ILK, ausr1, ausr1, ausr1, int256(100 * WAD), int256(90 * WAD));
    //     usr1.frob(ILK, ausr1, ausr1, ausr1, int256(100 * WAD), int256(90 * WAD));

    //     assertEq(usr1.dai(), 99 * RAD);
    //     assertEq(usr1.ink(ILK), 100 * WAD);
    //     assertEq(usr1.art(ILK), 90 * WAD);
    //     assertEq(usr1.gems(ILK), 0);
    //     assertEq(vat.Art(ILK), 90 * WAD);
    // }
}

contract IonPool_TestAdmin is IonPoolSharedSetup {
    // Random non admin address
    address internal immutable NON_ADMIN = vm.addr(33);

    function test_updateIlkSpot() external {
        uint256 newIlkSpot = 1.2e27;

        for (uint8 i = 0; i < collaterals.length; i++) {
            vm.expectRevert(IonPool.SpotUpdaterNotAuthorized.selector);
            vm.prank(NON_ADMIN);
            ionPool.updateIlkSpot(i, newIlkSpot);

            ionPool.updateIlkSpot(i, newIlkSpot);

            assertEq(ionPool.spot(i), newIlkSpot);
        }
    }

    function test_updateIlkDebtCeiling() external {
        uint256 newIlkDebtCeiling = 200e45;

        for (uint8 i = 0; i < collaterals.length; i++) {
            vm.expectRevert(
                bytes(
                    string.concat(
                        "AccessControl: account ",
                        uint256(uint160(NON_ADMIN)).toHexString(),
                        " is missing role ",
                        uint256(ionPool.ION()).toHexString()
                    )
                )
            );
            vm.prank(NON_ADMIN);
            ionPool.updateIlkDebtCeiling(i, newIlkDebtCeiling);

            ionPool.updateIlkDebtCeiling(i, newIlkDebtCeiling);

            assertEq(ionPool.debtCeiling(i), newIlkDebtCeiling);
        }
    }

    function test_updateIlkDust() external {
        uint256 newIlkDust = 2e45;

        for (uint8 i = 0; i < collaterals.length; i++) {
            vm.expectRevert(
                bytes(
                    string.concat(
                        "AccessControl: account ",
                        uint256(uint160(NON_ADMIN)).toHexString(),
                        " is missing role ",
                        uint256(ionPool.ION()).toHexString()
                    )
                )
            );
            vm.prank(NON_ADMIN);
            ionPool.updateIlkDust(i, newIlkDust);

            ionPool.updateIlkDust(i, newIlkDust);

            assertEq(ionPool.dust(i), newIlkDust);
        }
    }

    function test_updateIlkConfig() external {
        uint256 newIlkSpot = 1.2e27;
        uint256 newIlkDebtCeiling = 200e45;
        uint256 newIlkDust = 2e45;

        for (uint8 i = 0; i < collaterals.length; i++) {
            vm.expectRevert(
                bytes(
                    string.concat(
                        "AccessControl: account ",
                        uint256(uint160(NON_ADMIN)).toHexString(),
                        " is missing role ",
                        uint256(ionPool.ION()).toHexString()
                    )
                )
            );
            vm.prank(NON_ADMIN);
            ionPool.updateIlkConfig(i, newIlkSpot, newIlkDebtCeiling, newIlkDust);

            ionPool.updateIlkConfig(i, newIlkSpot, newIlkDebtCeiling, newIlkDust);

            assertEq(ionPool.spot(i), newIlkSpot);
            assertEq(ionPool.debtCeiling(i), newIlkDebtCeiling);
            assertEq(ionPool.dust(i), newIlkDust);
        }
    }

    function test_updateInterestRateModule() external {
        vm.expectRevert(IonPool.InvalidInterestRateModule.selector);
        ionPool.updateInterestRateModule(InterestRate(address(0)));

        // Random address
        InterestRate newInterestRateModule = InterestRate(address(732));
        // collateralCount will revert
        vm.expectRevert();
        ionPool.updateInterestRateModule(newInterestRateModule);

        IlkData[] memory invalidConfig = new IlkData[](collaterals.length - 1);

        uint16 previousDistributionFactor = ilkConfigs[0].distributionFactor;
        // Distribution factors need to sum to one
        ilkConfigs[0].distributionFactor = 0.6e2;
        for (uint256 i = 0; i < invalidConfig.length; i++) {
            invalidConfig[i] = ilkConfigs[i];
        }

        newInterestRateModule = new InterestRate(invalidConfig, apyOracle);

        vm.expectRevert(IonPool.InvalidInterestRateModule.selector);
        // collateralCount of the interest rate module will be less than the
        // ilkCount in IonPool
        ionPool.updateInterestRateModule(newInterestRateModule);

        ilkConfigs[0].distributionFactor = previousDistributionFactor;
        newInterestRateModule = new InterestRate(ilkConfigs, apyOracle);

        vm.expectRevert(
            bytes(
                string.concat(
                    "AccessControl: account ",
                    uint256(uint160(NON_ADMIN)).toHexString(),
                    " is missing role ",
                    uint256(ionPool.ION()).toHexString()
                )
            )
        );
        vm.prank(NON_ADMIN);
        ionPool.updateInterestRateModule(newInterestRateModule);

        ionPool.updateInterestRateModule(newInterestRateModule);

        assertEq(address(ionPool.interestRateModule()), address(newInterestRateModule));
    }

    // function test_pause() external {
    //     vm.expectRevert(
    //         bytes(
    //             string.concat(
    //                 "AccessControl: account ",
    //                 uint256(uint160(NON_ADMIN)).toHexString(),
    //                 " is missing role ",
    //                 uint256(ionPool.ION()).toHexString()
    //             )
    //         )
    //     );
    //     vm.prank(NON_ADMIN);
    //     ionPool.pause();

    //     ionPool.pause();
    //     assertEq(ionPool.paused(), true);

    //     vm.expectRevert("Pausable: paused");
    //     ionPool.pause();
    // }

    // function test_unpause() external {
    //     vm.expectRevert("Pausable: not paused");
    //     ionPool.unpause();

    //     ionPool.pause();
    //     assertEq(ionPool.paused(), true);

    //     vm.expectRevert(
    //         bytes(
    //             string.concat(
    //                 "AccessControl: account ",
    //                 uint256(uint160(NON_ADMIN)).toHexString(),
    //                 " is missing role ",
    //                 uint256(ionPool.ION()).toHexString()
    //             )
    //         )
    //     );
    //     vm.prank(NON_ADMIN);
    //     ionPool.unpause();

    //     ionPool.unpause();
    //     assertEq(ionPool.paused(), false);
    // }
}

// contract IonPool_TestPaused is IonPoolSharedSetup {
//     function test_RevertWhen_CallingFunctionsThatArePaused() external {
//         ionPool.pause();

//         vm.expectRevert("Pausable: paused");
//         ionPool.supply(address(0), 0);

//         vm.expectRevert("Pausable: paused");
//         ionPool.withdraw(address(0), 0);

//         vm.expectRevert("Pausable: paused");
//         ionPool.modifyPosition(0, address(0), address(0), address(0), 0, 0);

//         vm.expectRevert("Pausable: paused");
//         ionPool.mintAndBurnGem(0, address(0), 0);

//         vm.expectRevert("Pausable: paused");
//         ionPool.transferGem(0, address(0), address(0), 0);
//     }
// }
