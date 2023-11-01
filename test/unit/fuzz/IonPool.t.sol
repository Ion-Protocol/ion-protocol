// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { RoundedMath, RAY } from "src/libraries/math/RoundedMath.sol";

import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";

uint256 constant COLLATERAL_COUNT = 3;

// TODO: Test lender actions with changing supplyFactor
// TODO: Test borrow actions with changing rate
// TODO: Test borrow actions with changing rate and changing time
contract IonPool_FuzzTest is IonPoolSharedSetup {
    using RoundedMath for *;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Burn(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor);
    event Mint(address indexed user, address indexed underlyingFrom, uint256 amount, uint256 supplyFactor);

    event MintAndBurnGem(uint8 indexed ilkIndex, address indexed usr, int256 wad);
    event TransferGem(uint8 indexed ilkIndex, address indexed src, address indexed dst, uint256 wad);

    event WithdrawCollateral(uint8 indexed ilkIndex, address indexed user, address indexed recipient, uint256 amount);
    event DepositCollateral(uint8 indexed ilkIndex, address indexed user, address indexed depositor, uint256 amount);
    event Borrow(
        uint8 indexed ilkIndex,
        address indexed user,
        address indexed recipient,
        uint256 amountOfNormalizedDebt,
        uint256 ilkRate
    );
    event Repay(
        uint8 indexed ilkIndex,
        address indexed user,
        address indexed payer,
        uint256 amountOfNormalizedDebt,
        uint256 ilkRate
    );

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
            vm.prank(borrower1);
            collaterals[i].approve(address(gemJoins[i]), type(uint256).max);
        }
    }

    function test_setUp() public override {
        super.test_setUp();

        assertEq(ionPool.weth(), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(underlying.balanceOf(address(ionPool)), INITIAL_LENDER_UNDERLYING_BALANCE);
        assertEq(ionPool.balanceOf(lender2), INITIAL_LENDER_UNDERLYING_BALANCE);
    }

    function testFuzz_RevertWhen_SupplyingAboveSupplyCap(uint256 supplyAmount) public {
        vm.assume(supplyAmount < type(uint128).max && supplyAmount > 0);

        uint256 supplyCap = 0;
        ionPool.updateSupplyCap(supplyCap);
        vm.expectRevert(abi.encodeWithSelector(IonPool.DepositSurpassesSupplyCap.selector, supplyAmount, supplyCap));
        ionPool.supply(lender1, supplyAmount, new bytes32[](0));
    }

    function testFuzz_SupplyBase(uint256 supplyAmount) public {
        vm.assume(supplyAmount < type(uint128).max && supplyAmount > 0);

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        underlying.mint(lender1, supplyAmount);

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), lender1, supplyAmount);
        vm.expectEmit(true, true, true, true);
        emit Mint(lender1, lender1, supplyAmount, RAY);
        vm.prank(lender1);
        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount);
    }

    function testFuzz_SupplyBaseToDifferentAddress(uint256 supplyAmount) public {
        vm.assume(supplyAmount < type(uint128).max && supplyAmount > 0);

        underlying.mint(lender1, supplyAmount);

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), address(this), supplyAmount);
        vm.expectEmit(true, true, true, true);
        emit Mint(address(this), lender1, supplyAmount, RAY);
        vm.prank(lender1);
        ionPool.supply(address(this), supplyAmount, new bytes32[](0));

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(address(this)), supplyAmount);
    }

    function testFuzz_WithdrawBase(uint256 supplyAmount, uint256 withdrawAmount) public {
        vm.assume(supplyAmount < type(uint128).max && supplyAmount > 0);
        underlying.mint(lender1, supplyAmount);

        vm.startPrank(lender1);

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount);

        withdrawAmount = bound(withdrawAmount, 1, supplyAmount);

        vm.expectEmit(true, true, true, true);
        emit Transfer(lender1, address(0), withdrawAmount);
        vm.expectEmit(true, true, true, true);
        emit Burn(lender1, lender1, withdrawAmount, RAY);
        ionPool.withdraw(lender1, withdrawAmount);

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount - withdrawAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount - withdrawAmount);
    }

    function testFuzz_WithdrawBaseToDifferentAddress(uint256 supplyAmount, uint256 withdrawAmount) public {
        vm.assume(supplyAmount < type(uint128).max && supplyAmount > 0);
        underlying.mint(lender1, supplyAmount);

        vm.startPrank(lender1);

        uint256 supplyAmountBeforeSupply = ionPool.weth();

        ionPool.supply(lender1, supplyAmount, new bytes32[](0));

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount);

        withdrawAmount = bound(withdrawAmount, 1, supplyAmount);

        vm.expectEmit(true, true, true, true);
        emit Transfer(lender1, address(0), withdrawAmount);
        vm.expectEmit(true, true, true, true);
        emit Burn(lender1, address(this), withdrawAmount, RAY);
        ionPool.withdraw(address(this), withdrawAmount);

        assertEq(ionPool.weth(), supplyAmountBeforeSupply + supplyAmount - withdrawAmount);
        assertEq(ionPool.balanceOf(lender1), supplyAmount - withdrawAmount);
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
        require(COLLATERAL_COUNT == ionPool.ilkCount(), "IonPoolFuzz: Invalid Config");

        uint256 borrowedSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            // This 1:1 ratio is OK since ltv is set at 100%
            uint256 collateralDepositAmount = bound(collateralDepositAmounts[i], 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower1), borrowedSoFar);

            vm.expectEmit(true, true, true, true);
            emit Borrow(i, borrower1, borrower1, normalizedBorrowAmount, RAY);
            vm.prank(borrower1);
            ionPool.borrow(i, borrower1, borrower1, normalizedBorrowAmount, new bytes32[](0));

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);
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
        require(COLLATERAL_COUNT == ionPool.ilkCount(), "IonPoolFuzz: Invalid Config");

        uint256 borrowedSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            // This 1:1 ratio is OK since ltv is set at 100%
            uint256 collateralDepositAmount = bound(collateralDepositAmounts[i], 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower2), borrowedSoFar);

            vm.expectEmit(true, true, true, true);
            emit Borrow(i, borrower1, borrower2, normalizedBorrowAmount, RAY);
            vm.prank(borrower1);
            ionPool.borrow({
                ilkIndex: i,
                user: borrower1,
                recipient: borrower2,
                amountOfNormalizedDebt: normalizedBorrowAmount,
                proof: new bytes32[](0)
            });

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);
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
        require(COLLATERAL_COUNT == ionPool.ilkCount(), "IonPoolFuzz: Invalid Config");

        uint256 borrowedSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            // This 1:1 ratio is OK since ltv is set at 100%
            uint256 collateralDepositAmount = bound(collateralDepositAmounts[i], 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            assertEq(ionPool.collateral(i, borrower1), collateralDepositAmount);
            assertEq(underlying.balanceOf(borrower2), borrowedSoFar);

            vm.prank(borrower1);
            ionPool.addOperator(borrower2);

            vm.expectEmit(true, true, true, true);
            emit Borrow(i, borrower1, borrower2, normalizedBorrowAmount, RAY);
            vm.prank(borrower2);
            ionPool.borrow({
                ilkIndex: i,
                user: borrower1,
                recipient: borrower2,
                amountOfNormalizedDebt: normalizedBorrowAmount,
                proof: new bytes32[](0)
            });

            uint256 liquidityRemoved = normalizedBorrowAmount.rayMulDown(rate);
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

    function testFuzz_Repay(
        uint256 collateralDepositAmount,
        uint256 normalizedBorrowAmount,
        uint256 normalizedRepayAmount
    )
        public
    {
        vm.prank(borrower1);
        underlying.approve(address(ionPool), type(uint256).max);

        uint256 borrowedSoFar;
        uint256 repaidSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            collateralDepositAmount = bound(collateralDepositAmount, 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount);
            normalizedRepayAmount = bound(normalizedRepayAmount, 0, normalizedBorrowAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

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
            emit Repay(i, borrower1, borrower1, normalizedRepayAmount, rate);
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

        uint256 borrowedSoFar;
        uint256 repaidSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            collateralDepositAmount = bound(collateralDepositAmount, 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount);
            normalizedRepayAmount = bound(normalizedRepayAmount, 0, normalizedBorrowAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);
            uint256 trueRepayAmount = normalizedRepayAmount.rayMulUp(rate);

            underlying.mint(borrower2, trueRepayAmount);

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
            emit Repay(i, borrower1, borrower2, normalizedRepayAmount, rate);
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

        uint256 borrowedSoFar;
        uint256 repaidSoFar;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            collateralDepositAmount = bound(collateralDepositAmount, 0, debtCeilings[i].scaleDownToWad(45));
            normalizedBorrowAmount = bound(normalizedBorrowAmount, 0, collateralDepositAmount);
            normalizedRepayAmount = bound(normalizedRepayAmount, 0, normalizedBorrowAmount);

            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.startPrank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);
            ionPool.depositCollateral(i, borrower1, borrower1, collateralDepositAmount, new bytes32[](0));
            vm.stopPrank();

            uint256 rate = ionPool.rate(i);
            uint256 liquidityBefore = ionPool.weth();

            uint256 trueBorrowAmount = normalizedBorrowAmount.rayMulDown(rate);
            uint256 trueRepayAmount = normalizedRepayAmount.rayMulUp(rate);

            underlying.mint(borrower2, trueRepayAmount);

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
            emit Repay(i, borrower1, borrower2, normalizedRepayAmount, rate);
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

    function testFuzz_RevertWhen_TransferGemOnBehalfWithoutConsent(uint256 collateralDepositAmount, uint256 transferAmount) external {
        vm.assume(collateralDepositAmount < type(uint128).max);
        transferAmount = bound(transferAmount, 0, collateralDepositAmount);

        for (uint8 i = 0; i < collaterals.length; i++) {
            ERC20PresetMinterPauser collateral = ERC20PresetMinterPauser(address(collaterals[i]));
            collateral.mint(borrower1, collateralDepositAmount);

            vm.prank(borrower1);
            gemJoins[i].join(borrower1, collateralDepositAmount);

            vm.expectRevert(
                abi.encodeWithSelector(IonPool.GemTransferWithoutConsent.selector, i, borrower1, borrower2)
            );
            vm.prank(borrower2);
            ionPool.transferGem(i, borrower1, borrower2, transferAmount);
        }
    }

    function testFuzz_TransferGemOnBehalfWithConsent(uint256 collateralDepositAmount, uint256 transferAmount) external {
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
