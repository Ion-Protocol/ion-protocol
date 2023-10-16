// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {LiquidationSharedSetup} from "test/helpers/LiquidationSharedSetup.sol";
// import { RoundedMath, WAD, RAY } from "../../src/math/RoundedMath.sol";
import { Liquidation } from "src/Liquidation.sol"; 
import "forge-std/console.sol";


// Traces:
//  [2261284] LiquidationFuzzTest::testFuzz_AssertCheckFixedConfigsNoRate(6554, 2447769056616533639 [2.447e18], 14066 [1.406e4])


// 1377293678788981892 * 1 ether * 0.8 ether / 1 ether =  
// 

// depositAmt, borrowAmt, exchangeRate 2, 1, 250000000000000000
// depositAmt, borrowAmt, exchangeRate 
// depositAmt, borrowAmt, exchangeRate 
contract LiquidationFuzzTest is LiquidationSharedSetup {
    // using RoundedMath for uint256; 
    address constant REVENUE_RECIPIENT = address(1);
    address constant BORROWER = address(2);  
    address constant LENDER = address(3);  
    address constant KEEPER = address(4);  
    uint8 constant ILK_INDEX = 0; 

    function getHealthRatio() public view {

    }

    function testFuzz_AssertCheckFixedConfigsNoRate(
        uint256 exchangeRate, 
        uint256 depositAmt, 
        uint256 borrowAmt
    ) external {
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

        // constraints 
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

    function testFuzz_ProtocolLiquidation(

    ) public {

    }

    // function testFuzz_AllOutputBranchesFixedConfigNoRate(

    // ) {
    //     // if partial liquidation 
    //     // if dust liquidation 
    //     // if protocol liquidation 
    // }

    function testFuzz_AssertCheckFuzzedConfigsNoRate(
        uint256 exchangeRate, 
        uint256 depositAmt, 
        uint256 borrowAmt
    ) public {

    }

    /**
     * Assumes that the target health, liquidation threshold, and discount is correctly set. 
     * Assume targetHealth is above 1. 
     * Assume targetHealth - (liquidationThreshold / 1 - discount) > 0 

     * Set maxDiscount = 1 - 1 / targetHealth 
     * What is the bound for exchangeRate? 
     * How to make sure this is a partial liquidation scenario? 
     * Bound using the partial liquidation math
     * Bound assuming dust exists 
     * Bound assuming partial liquidation is not possible 
     */
    // function testFuzz_PartialLiquidationWithoutReserveFactor(
    //     uint256 targetHealth,
    //     uint256 liquidationThreshold, 
    //     uint256 discount

        
    //     ) external {
    //     uint256 reserveFactor = 0; 

    //     vm.assume(liquidationThreshold < 1 ether && liquidationThreshold > 0 ether); 
    //     vm.assume(targetHealth > 1 ether  && targetHealth < 1.25 ether); 
    //     uint256 maxDiscount = WAD - WAD.wadDivDown(targetHealth);

    //     vm.assume(discount < maxDiscount);  
    //     vm.assume(targetHealth - liquidationThreshold.wadDivDown(WAD - discount) > 0); 

    //     // instantiate liquidations contract 
    //     uint64[ILK_COUNT] memory liquidationThresholds = [uint64(liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
    //     liquidation = new Liquidation(
    //         address(ionPool), 
    //         address(reserveOracle), 
    //         revenueRecipient, 
    //         liquidationThresholds,
    //         targetHealth,
    //         reserveFactor,  
    //         maxDiscount 
    //     );

    //     // liquidate 
    //     vm.prank()

    // }

    // function testFuzz_PartialLiquidationWithReserveFactor() external {

    // }

    // property that is maintained right after liquidations 
    // function invariant_property() public returns (bool) {

    // }

    // // resulting health ratio after liquidation must be the targetHealth parameter
    // // targetHealth, maxDiscount, and [] has a relationship  
    // // collateral, rate, normalized debt, exchange rate can be anything
    // function invariant_TargetHealthRatioReached() public returns (bool) {
    //     uint256 healthRatio = 1.25 ether; 
    // }

    // check assertion that after liquidations, the healthRatio is 1.25 
    // but it's only 1.25 under certain constraints 

}