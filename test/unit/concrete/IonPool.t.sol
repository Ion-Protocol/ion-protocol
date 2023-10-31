// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GemJoin } from "src/join/GemJoin.sol";
import { IonPool } from "src/IonPool.sol";
import { WAD, RAY, RAD, RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { InterestRate, IlkData } from "src/InterestRate.sol";
import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";
import { IonPausableUpgradeable } from "src/admin/IonPausableUpgradeable.sol";

import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

using Strings for uint256;
using RoundedMath for uint256;

contract IonPool_Test is IonPoolSharedSetup {
    function setUp() public override {
        super.setUp();

        ERC20PresetMinterPauser(_getUnderlying()).mint(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        ERC20PresetMinterPauser(_getUnderlying()).mint(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender2);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender2, INITIAL_LENDER_UNDERLYING_BALANCE, new bytes32[](0));
        vm.stopPrank();
    }

    function test_setUp() public override {
        assertEq(ionPool.weth(), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(ionPool.balanceOf(lender2), INITIAL_LENDER_UNDERLYING_BALANCE);
    }


    function test_BasicLendAndWithdraw() external {
        vm.startPrank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, INITIAL_LENDER_UNDERLYING_BALANCE, new bytes32[](0));

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

    // Random non admin address
    address internal immutable NON_ADMIN = vm.addr(33);

    function test_initializeIlk() external {
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

    function test_updateIlkSpot() external {
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

    function test_updateIlkDebtCeiling() external {
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

    function test_updateIlkDust() external {
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

    function test_updateInterestRateModule() external {
        vm.expectRevert(IonPool.InvalidInterestRateModule.selector);
        ionPool.updateInterestRateModule(InterestRate(address(0)));

        // Random address
        InterestRate newInterestRateModule = InterestRate(address(732));
        // collateralCount will revert
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

        vm.expectRevert(IonPool.InvalidInterestRateModule.selector);
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

    function test_pauseUnsafeActions() external {
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

    function test_unpauseUnsafeActions() external {
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

    function test_pauseSafeActions() external {
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

    function test_unpauseSafeActions() external {
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
}

contract IonPool_PausedTest is IonPoolSharedSetup {
    function test_RevertWhen_CallingUnsafeFunctionsWhenPausedUnsafe() external {
        ionPool.pauseUnsafeActions();

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE));
        ionPool.withdraw(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE));
        ionPool.borrow(0, address(0), address(0), 0, new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE));
        ionPool.withdrawCollateral(0, address(0), address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE));
        ionPool.mintAndBurnGem(0, address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.UNSAFE));
        ionPool.transferGem(0, address(0), address(0), 0);
    }

    function test_RevertWhen_CallingSafeFunctionsWhenPausedSafe() external {
        ionPool.pauseSafeActions();

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE));
        ionPool.accrueInterest();

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE));
        ionPool.supply(address(0), 0, new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE));
        ionPool.repay(0, address(0), address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE));
        ionPool.depositCollateral(0, address(0), address(0), 0, new bytes32[](0));

        vm.expectRevert(abi.encodeWithSelector(IonPausableUpgradeable.EnforcedPause.selector, IonPausableUpgradeable.Pauses.SAFE));
        ionPool.repayBadDebt(address(0), 0);
    }
}
