// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { YieldOracle } from "../../../src/YieldOracle.sol";
import { WeEthIonPoolSharedSetup } from "../../helpers/weETH/WeEthIonPoolSharedSetup.sol";
import { Whitelist } from "../../../src/Whitelist.sol";
import { WSTETH_ADDRESS, WEETH_ADDRESS, EETH_ADDRESS } from "../../../src/Constants.sol";
import { IWstEth, IWeEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { LidoLibrary } from "../../../src/libraries/LidoLibrary.sol";
import { EtherFiLibrary } from "../../../src/libraries/EtherFiLibrary.sol";
import { SpotOracle } from "../../../src/oracles/spot/SpotOracle.sol";
import { WeEthWstEthReserveOracle } from "../../../src/oracles/reserve/WeEthWstEthReserveOracle.sol";
import { WeEthWstEthSpotOracle } from "../../../src/oracles/spot/WeEthWstEthSpotOracle.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using LidoLibrary for IWstEth;
using EtherFiLibrary for IWeEth;
using Math for uint256;

contract WeEthIonPool_IntegrationTest is WeEthIonPoolSharedSetup {
    // generate merkle root
    // ["0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496"],
    // ["0x2222222222222222222222222222222222222222"],
    // => 0xb51a382d5bcb4cd5fe50a7d4d8abaf056ac1a6961cf654ec4f53a570ab75a30b

    bytes32 borrowerWhitelistRoot = 0x846dfddafc70174f2089edda6408bf9dd643c19ee06ff11643b614f0e277d6e3;

    bytes32[][] borrowerProofs = [
        [bytes32(0x708e7cb9a75ffb24191120fba1c3001faa9078147150c6f2747569edbadee751)],
        [bytes32(0xa6e6806303186f9c20e1af933c7efa83d98470acf93a10fb8da8b1d9c2873640)]
    ];

    // generate merkle root
    // ["0x0000000000000000000000000000000000000001"],
    // ["0x0000000000000000000000000000000000000002"],
    // ["0x0000000000000000000000000000000000000003"],
    // ["0x0000000000000000000000000000000000000004"],
    // ["0x0000000000000000000000000000000000000005"],
    // => 0x21abd2f655ded75d91fbd5e0b1ad35171a675fd315a077efa7f2d555a26e7094

    bytes32 lenderRoot = 0x21abd2f655ded75d91fbd5e0b1ad35171a675fd315a077efa7f2d555a26e7094;

    // Proofs for address(1) and address(3)
    bytes32[][] lenderProofs = [
        [
            bytes32(0x2584db4a68aa8b172f70bc04e2e74541617c003374de6eb4b295e823e5beab01),
            bytes32(0xc949c2dc5da2bd9a4f5ae27532dfbb3551487bed50825cd099ff5d0a8d613ab5)
        ],
        [
            bytes32(0xb5d9d894133a730aa651ef62d26b0ffa846233c74177a591a4a896adfda97d22),
            bytes32(0xc949c2dc5da2bd9a4f5ae27532dfbb3551487bed50825cd099ff5d0a8d613ab5)
        ]
    ];

    uint256 internal constant INITIAL_ETHER_BALANCE = 10_000e18;
    uint256 internal constant LST_ETHER_DEPOSIT_AMOUNT = 5000e18;

    address lenderA = address(1);
    address lenderB = address(3);

    address borrowerA = address(this);
    address borrowerB = address(0x2222222222222222222222222222222222222222);

    WeEthWstEthReserveOracle reserveOracle;
    WeEthWstEthSpotOracle spotOracle;

    uint256 internal constant DEBT_CEILING = 10_000e45;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        uint256 maxChange = 0.03e27;
        reserveOracle = new WeEthWstEthReserveOracle(0, new address[](3), 0, maxChange);

        uint256 maxTimeFromLastUpdate = 1 days;
        uint256 ltv = 0.8e27;
        spotOracle = new WeEthWstEthSpotOracle(ltv, address(reserveOracle), maxTimeFromLastUpdate);

        config.minimumProfitMargins[0] = 0;
        config.minimumKinkRates[0] = 4_062_570_058_138_700_000;
        config.reserveFactors[0] = 0;
        config.adjustedBaseRates[0] = 0;
        config.minimumBaseRates[0] = 1_580_630_071_273_960_000;
        config.optimalUtilizationRates[0] = 8500;
        config.adjustedAboveKinkSlopes[0] = 0;
        config.minimumAboveKinkSlopes[0] = 23_863_999_665_252_300_000;

        super.setUp();

        ionPool.updateSupplyCap(10_000 ether);

        vm.deal(lenderA, INITIAL_ETHER_BALANCE);
        vm.prank(lenderA);
        WSTETH_ADDRESS.depositForLst(LST_ETHER_DEPOSIT_AMOUNT);

        vm.deal(lenderB, INITIAL_ETHER_BALANCE);
        vm.prank(lenderB);
        WSTETH_ADDRESS.depositForLst(LST_ETHER_DEPOSIT_AMOUNT);

        // For borrowerA (address(this))
        EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
        WEETH_ADDRESS.depositForLrt(LST_ETHER_DEPOSIT_AMOUNT);

        vm.deal(borrowerB, INITIAL_ETHER_BALANCE);
        vm.startPrank(borrowerB);
        EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
        WEETH_ADDRESS.depositForLrt(LST_ETHER_DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    function test_LenderAndBorrowerUserFlow() public {
        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                           ACTION 1                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedLender.selector, borrowerA));
        ionPool.supply(borrowerA, 1, new bytes32[](0));

        uint256 lenderAFirstSupplyAmount = 500e18;

        vm.startPrank(lenderA);
        WSTETH_ADDRESS.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lenderA, lenderAFirstSupplyAmount, lenderProofs[0]);
        vm.stopPrank();

        assertEq(ionPool.balanceOf(lenderA), lenderAFirstSupplyAmount, "lender balance after 1st supply");
        assertEq(ionPool.weth(), lenderAFirstSupplyAmount, "liquidity after 1st supply");

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                           ACTION 2                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        uint256 borrowerADepositAmount1 = 700e18;
        uint256 borrowerABorrowAmount1 = 350e18;

        // BorrowerA (address(this))
        WEETH_ADDRESS.approve(address(gemJoins[0]), type(uint256).max);
        gemJoins[0].join(borrowerA, borrowerADepositAmount1);
        ionPool.depositCollateral(0, borrowerA, borrowerA, borrowerADepositAmount1, borrowerProofs[0]);
        ionPool.borrow(0, borrowerA, borrowerA, borrowerABorrowAmount1, borrowerProofs[0]);

        assertEq(
            WSTETH_ADDRESS.balanceOf(borrowerA), borrowerABorrowAmount1, "borrowerA wstETH balance after 1st borrow"
        );
        assertEq(
            ionPool.normalizedDebt(0, borrowerA).mulDiv(ionPool.rate(0), 1e27, Math.Rounding.Ceil),
            borrowerABorrowAmount1,
            "borrowerA debt after 1st borrow"
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                           ACTION 3                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.warp(block.timestamp + 172);

        assertGe(
            ionPool.normalizedDebt(0, borrowerA).mulDiv(ionPool.rate(0), 1e27, Math.Rounding.Ceil),
            borrowerABorrowAmount1,
            "borrowerA debt should increase with time passing"
        );

        uint256 lenderBFirstSupplyAmount = 100e18;

        vm.startPrank(lenderB);
        WSTETH_ADDRESS.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lenderB, lenderBFirstSupplyAmount, lenderProofs[1]);
        vm.stopPrank();

        uint256 roundingError = ionPool.supplyFactor() / 1e27;

        assertApproxEqAbs(
            ionPool.balanceOf(lenderB), lenderBFirstSupplyAmount, roundingError, "lenderB balance after 1st supply"
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                           ACTION 4                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.warp(block.timestamp + 597);

        uint256 borrowerBDepositAmount1 = 500e18;
        uint256 borrowerBBorrowAmount1 = 200e18;
        uint256 normalizedBorrowerBBorrowAmount1 =
            borrowerBBorrowAmount1.mulDiv(1e27, ionPool.rate(0), Math.Rounding.Ceil);

        vm.startPrank(borrowerB);
        WEETH_ADDRESS.approve(address(gemJoins[0]), type(uint256).max);
        gemJoins[0].join(borrowerB, borrowerADepositAmount1);
        ionPool.depositCollateral(0, borrowerB, borrowerB, borrowerBDepositAmount1, borrowerProofs[1]);
        ionPool.borrow(0, borrowerB, borrowerB, normalizedBorrowerBBorrowAmount1, borrowerProofs[1]);
        vm.stopPrank();

        assertEq(
            ionPool.normalizedDebt(0, borrowerB),
            normalizedBorrowerBBorrowAmount1,
            "borrowerB normalized debt after 1st borrow"
        );
        assertEq(
            WSTETH_ADDRESS.balanceOf(borrowerB), borrowerBBorrowAmount1, "borrowerB wstETH balance after 1st borrow"
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                           ACTION 5                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.warp(block.timestamp + 56);

        // Not enough liquidity to service this withdrawal
        uint256 lender1WithdrawAmountFail = 100e18;

        // Should underflow
        vm.expectRevert();
        vm.startPrank(lenderA);
        ionPool.withdraw(lenderA, lender1WithdrawAmountFail);

        uint256 lenderABalanceBefore = ionPool.balanceOf(lenderA);

        uint256 lender1WithdrawAmount = 10e18;
        ionPool.withdraw(lenderA, lender1WithdrawAmount);
        vm.stopPrank();

        assertEq(
            ionPool.balanceOf(lenderA),
            lenderABalanceBefore - lender1WithdrawAmount,
            "lenderA balance after 1st withdrawal"
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                           ACTION 6                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.warp(block.timestamp + 812);

        uint256 borrowerBRepayAmount1 = 100e18;

        uint256 normalizedDebtBeforeRepay = ionPool.normalizedDebt(0, borrowerB);

        vm.startPrank(borrowerB);
        WSTETH_ADDRESS.approve(address(ionPool), type(uint256).max);
        ionPool.repay(0, borrowerB, borrowerB, borrowerBRepayAmount1);

        assertEq(
            ionPool.normalizedDebt(0, borrowerB),
            normalizedDebtBeforeRepay - borrowerBRepayAmount1,
            "borrowerB normalized debt after 1st repayment"
        );

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                           ACTION 7                         */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

        vm.warp(block.timestamp + 329);

        uint256 borrowerBRepayOnBehalfOfAAmount = 30e18;

        uint256 normalizedDebtABefore = ionPool.normalizedDebt(0, borrowerA);

        ionPool.repay(0, borrowerA, borrowerB, borrowerBRepayOnBehalfOfAAmount);
        vm.stopPrank();

        assertEq(
            ionPool.normalizedDebt(0, borrowerA),
            normalizedDebtABefore - borrowerBRepayOnBehalfOfAAmount,
            "borrowerA normalized debt after repayment from B on behalf of borrowerA"
        );
    }

    function _getSpot() internal view override returns (uint256) {
        return spotOracle.getSpot();
    }

    function _getDebtCeiling(uint8) internal pure override returns (uint256) {
        return DEBT_CEILING;
    }

    function _getSpotOracle() internal view override returns (SpotOracle) {
        return spotOracle;
    }

    function _getWhitelist() internal override returns (Whitelist) {
        bytes32[] memory borrowerWhitelist = new bytes32[](1);
        borrowerWhitelist[0] = borrowerWhitelistRoot;

        return new Whitelist(borrowerWhitelist, lenderRoot);
    }
}
