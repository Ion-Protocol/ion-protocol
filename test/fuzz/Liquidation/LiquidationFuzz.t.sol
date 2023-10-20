// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidationSharedSetup } from "test/helpers/LiquidationSharedSetup.sol";
import { RoundedMath, WAD, RAY } from "src/math/RoundedMath.sol";
import { Liquidation } from "src/Liquidation.sol";
import "forge-std/console.sol";

// Traces:
//  [2261284] LiquidationFuzzTest::testFuzz_AssertCheckFixedConfigsNoRate(6554, 2447769056616533639 [2.447e18], 14066
// [1.406e4])

// 1377293678788981892 * 1 ether * 0.8 ether / 1 ether =
//

// depositAmt, borrowAmt, exchangeRate 2, 1, 250000000000000000
// depositAmt, borrowAmt, exchangeRate
// depositAmt, borrowAmt, exchangeRate
contract LiquidationFuzzTest is LiquidationSharedSetup {
    using RoundedMath for uint256;

    address constant REVENUE_RECIPIENT = address(1);
    address constant BORROWER = address(2);
    address constant LENDER = address(3);
    address constant KEEPER = address(4);
    uint8 constant ILK_INDEX = 0;

    function getHealthRatio() public view { }

    // function testFuzz_GemOutAndRepay(

    // ) external {

    // }

    function testFuzz_CheckAllAssertsFixedConfigsNoRate(
        uint256 exchangeRate,
        uint256 depositAmt,
        uint256 borrowAmt
    )
        external
    {
        LiquidationArgs memory args;

        // configs
        uint256 startingExchangeRate = 1 ether;

        depositAmt = bound(depositAmt, 1 ether, 100 ether);
        borrowAmt = bound(borrowAmt, 1 ether, 100 ether);
        exchangeRate = bound(exchangeRate, 1, startingExchangeRate); // exchangeRate < startingExchangeRate

        args.targetHealth = 1.25 ether;
        args.liquidationThreshold = 0.8 ether;
        args.maxDiscount = 0.2 ether;
        args.reserveFactor = 0;

        args.collateral = depositAmt;
        args.exchangeRate = exchangeRate;
        args.normalizedDebt = borrowAmt; // No rate
        args.rate = 1 * RAY;

        // starting position must be safe
        vm.assume(borrowAmt * WAD / depositAmt < args.liquidationThreshold);

        // new exchangeRate needs to result in healthRatio < 1
        console.log("assume: ", depositAmt * exchangeRate / WAD * args.liquidationThreshold / borrowAmt);

        vm.assume(depositAmt * exchangeRate / WAD * args.liquidationThreshold / borrowAmt < 1 ether);

        // expected results
        Results memory results = calculateExpectedLiquidationResults(args);

        // constrain exchangeRate to make vault unsafe
        // [wad] * [wad] / [wad] * [wad] / [wad] = [wad]
        // vm.assume(depositAmt * exchangeRate / WAD * args.liquidationThreshold / borrowAmt < 1 ether);

        // instantiate liquidations contract
        uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
        liquidation = new Liquidation(
            address(ionPool), 
            address(reserveOracle), 
            REVENUE_RECIPIENT, 
            liquidationThresholds,
            args.targetHealth,
            args.reserveFactor,  
            args.maxDiscount 
        );
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // lender
        supply(LENDER, borrowAmt);
        // borrower makes a SAFE position
        borrow(BORROWER, ILK_INDEX, depositAmt, borrowAmt);

        // exchangeRate changes based on fuzz
        reserveOracle.setExchangeRate(exchangeRate);

        // keeper
        liquidate(KEEPER, ILK_INDEX, BORROWER);
    }

    function testFuzz_ProtocolLiquidationFixedConfigsNoRate(
        uint256 exchangeRate,
        uint256 depositAmt,
        uint256 borrowAmt
    )
        public
    {
        LiquidationArgs memory args;
        // protocol liquidations occur in cases of bad debt
        // if (gemOut > collateral) then (repay == normalizedDebt * rate)

        uint256 startingExchangeRate = 1 ether;

        depositAmt = bound(depositAmt, 1 ether, 100 ether);
        borrowAmt = bound(borrowAmt, 1 ether, 100 ether);
        exchangeRate = bound(exchangeRate, 1, startingExchangeRate);

        args.targetHealth = 1.25 ether;
        args.liquidationThreshold = 0.8 ether;
        args.maxDiscount = 0.2 ether;
        args.reserveFactor = 0;

        args.collateral = depositAmt;
        args.exchangeRate = exchangeRate;
        args.normalizedDebt = borrowAmt;
        args.rate = 1 * RAY;

        // starting position must be safe
        vm.assume(borrowAmt * WAD / depositAmt < args.liquidationThreshold);

        // to avoid overflow in calculateExpectedLiquidationResults, healthRatio must be less than 1
        vm.assume(depositAmt * exchangeRate / WAD * args.liquidationThreshold / borrowAmt < 1 ether);

        // should generate bad debt
        Results memory results = calculateExpectedLiquidationResults(args);
        results.gemOut = results.gemOut.scaleToWad(27);
        results.repay = results.repay.scaleToWad(27);

        vm.assume(results.gemOut >= depositAmt);
        vm.assume(results.repay > borrowAmt); // NOTE: actual condition being checked in liquidations

        uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
        liquidation = new Liquidation(
            address(ionPool), 
            address(reserveOracle), 
            REVENUE_RECIPIENT, 
            liquidationThresholds,
            args.targetHealth,
            args.reserveFactor,  
            args.maxDiscount 
        );
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // lender
        supply(LENDER, borrowAmt);

        // borrower makes a SAFE position
        borrow(BORROWER, ILK_INDEX, depositAmt, borrowAmt);

        // exchangeRate changes based on fuzz
        reserveOracle.setExchangeRate(exchangeRate);

        // keeper
        liquidate(KEEPER, ILK_INDEX, BORROWER);

        // results
        // if bad debt => protocol confiscates, resulting normalized and collateral is both zero
        console.log("collateral: ", ionPool.collateral(ilkIndex, BORROWER));
        console.log("debt: ", ionPool.normalizedDebt(ilkIndex, BORROWER));
        assert(ionPool.collateral(ilkIndex, BORROWER) == 0);
        assert(ionPool.normalizedDebt(ilkIndex, BORROWER) == 0);
    }

    function testFuzz_DustLiquidationFixedConfigsNoRate(
        uint256 exchangeRate,
        uint256 depositAmt,
        uint256 borrowAmt
    )
        public
    {
        LiquidationArgs memory args;
        uint256 startingExchangeRate = 1 ether;

        // update dust
        ionPool.updateIlkDust(ilkIndex, uint256(0.5 ether).scaleToRad(18)); // [rad]
        uint256 dust = ionPool.dust(ilkIndex);

        depositAmt = bound(depositAmt, 1 ether, 100 ether);
        borrowAmt = bound(borrowAmt, dust.scaleToWad(45), 100 ether); // dust is minimum borrow
        exchangeRate = bound(exchangeRate, 1, startingExchangeRate);

        args.targetHealth = 1.25 ether;
        args.liquidationThreshold = 0.8 ether;
        args.maxDiscount = 0.2 ether;
        args.reserveFactor = 0;

        args.collateral = depositAmt;
        args.exchangeRate = exchangeRate;
        args.normalizedDebt = borrowAmt;
        args.rate = 1 * RAY;

        // starting position must be safe
        vm.assume(borrowAmt * WAD / depositAmt < args.liquidationThreshold);

        // to avoid overflow in calculateExpectedLiquidationResults, healthRatio must be less than 1
        vm.assume(depositAmt * exchangeRate / WAD * args.liquidationThreshold / borrowAmt < 1 ether);

        // expected results
        Results memory results = calculateExpectedLiquidationResults(args);
        results.gemOut = results.gemOut.scaleToWad(27);
        results.repay = results.repay.scaleToWad(27);

        // should not be a protocol liquidation (i.e. no bad debt)
        vm.assume(results.repay <= borrowAmt);
        vm.assume(results.gemOut <= depositAmt);

        // but should leave dust
        console.log("borrowAmt * args.rate: ", borrowAmt * args.rate);
        console.log("results.repay rad: ", results.repay.scaleToRad(18));
        console.log("dust: ", dust);
        vm.assume(borrowAmt * args.rate - results.repay.scaleToRad(18) < dust);

        // actions
        uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
        liquidation = new Liquidation(
            address(ionPool), 
            address(reserveOracle), 
            REVENUE_RECIPIENT, 
            liquidationThresholds,
            args.targetHealth,
            args.reserveFactor,  
            args.maxDiscount 
        );
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // lender
        supply(LENDER, borrowAmt);

        // borrower makes a SAFE position
        borrow(BORROWER, ILK_INDEX, depositAmt, borrowAmt);

        // exchangeRate changes based on fuzz
        reserveOracle.setExchangeRate(exchangeRate);

        // keeper
        liquidate(KEEPER, ILK_INDEX, BORROWER);

        // results
        assert(ionPool.normalizedDebt(ilkIndex, BORROWER) == 0);
    }

    function testFuzz_FuzzAllVariablesForAllOutcomesWithRate() public {
        // bound each variable to realistic numberes
        // if partial liquidation then assert
        // if dust lquidation then assert
        // if protocol liquidation then assert
    }
}
