// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidationSharedSetup } from "test/helpers/LiquidationSharedSetup.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";
import { Liquidation } from "src/Liquidation.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "forge-std/console.sol";

/**
 * Fixes deployment configs and fuzzes potential states
 */
contract LiquidationFuzzFixedConfigsFixedRate is LiquidationSharedSetup {
    using WadRayMath for uint256;
    using SafeCast for *;

    DeploymentArgs internal deploymentArgs;
    StateArgs internal stateArgs;

    uint256 internal minDepositAmt;
    uint256 internal maxDepositAmt;
    uint256 internal minBorrowAmt;
    uint256 internal maxBorrowAmt;
    uint256 internal minExchangeRate;
    uint256 internal maxExchangeRate;

    uint256 internal startingExchangeRate;

    uint256 constant NO_RATE = 1e27;

    function setUp() public override {
        super.setUp();

        // default configs
        deploymentArgs.targetHealth = 1.25e27; // [ray]
        deploymentArgs.reserveFactor = 0.02e27; // [ray]
        deploymentArgs.maxDiscount = 0.2e27; // [ray]
        deploymentArgs.liquidationThreshold = 0.9e27; // [ray]

        deploymentArgs.dust = 10e18;
        ionPool.updateIlkDust(ilkIndex, deploymentArgs.dust);

        // fuzz configs
        minDepositAmt = 1;
        maxDepositAmt = 10_000e18;
        minBorrowAmt = 1;
        maxBorrowAmt = 10_000e18;
        minExchangeRate = 1; // overflows if zero because collateral value becomes zero
        startingExchangeRate = 1e18;
    }

    // function testFuzz_RepayGemOutEquivalenceFormula(
    //     uint256 depositAmt,
    //     uint256 borrowAmt,
    //     uint256 exchangeRate
    // ) public {
    //     stateArgs.collateral = bound(depositAmt, minDepositAmt, maxDepositAmt);
    //     stateArgs.normalizedDebt = bound(borrowAmt, minDepositAmt, maxDepositAmt);
    //     stateArgs.exchangeRate = bound(exchangeRate, minExchangeRate, startingExchangeRate);

    //     // starting position must be safe
    //     vm.assume(stateArgs.normalizedDebt * NO_RATE < stateArgs.collateral * deploymentArgs.liquidationThreshold);

    //     uint256 liabilityValue = stateArgs.normalizedDebt * NO_RATE;

    //     // fuzzes asserts in helper function
    //     Results memory results = calculateExpectedLiquidationResults(deploymentArgs, stateArgs);

    //     // if repay > liabilityValue, then gemOut > collateral
    //     if (results.repay > liabilityValue) {
    //         assert(results.gemOut > stateArgs.collateral);
    //     } else {
    //         assert(results.gemOut <= stateArgs.collateral);
    //     }
    // }

    /**
     * In a partial liquidation scenario, target health ratio should always be reached.
     */
    function testFuzz_AllLiquidationCategories(uint256 depositAmt, uint256 borrowAmt, uint256 exchangeRate) public {
        // state args
        StateArgs memory stateArgs;
        stateArgs.collateral = bound(depositAmt, minDepositAmt, maxDepositAmt);
        stateArgs.normalizedDebt = bound(borrowAmt, minDepositAmt, maxDepositAmt);
        stateArgs.exchangeRate = bound(exchangeRate, minExchangeRate, startingExchangeRate); // [wad]
        stateArgs.rate = NO_RATE;

        // starting position must be safe
        // [wad] * [ray] <= [wad] * [ray]
        vm.assume(
            stateArgs.normalizedDebt * stateArgs.rate
                <= (stateArgs.collateral * startingExchangeRate.scaleUpToRay(18)).rayMulDown(
                    deploymentArgs.liquidationThreshold
                )
        );

        // position needs to be unsafe after exchange rate change
        vm.assume(
            stateArgs.normalizedDebt * stateArgs.rate
                > (stateArgs.collateral * stateArgs.exchangeRate.scaleUpToRay(18)).rayMulDown(
                    deploymentArgs.liquidationThreshold
                )
        );

        Results memory results = calculateExpectedLiquidationResults(deploymentArgs, stateArgs);

        // liquidations contract
        uint256[ILK_COUNT] memory liquidationThresholds = [deploymentArgs.liquidationThreshold, 0, 0, 0, 0, 0, 0, 0];
        liquidation = new Liquidation(
            address(ionPool), 
            revenueRecipient, 
            protocol,
            exchangeRateOracles, 
            liquidationThresholds, 
            deploymentArgs.targetHealth, 
            deploymentArgs.reserveFactor, 
            deploymentArgs.maxDiscount
        );
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // lender
        supply(lender1, stateArgs.normalizedDebt);
        // borrower makes a SAFE position
        borrow(borrower1, ilkIndex, stateArgs.collateral, stateArgs.normalizedDebt);
        // exchange rate changes based on fuzz
        reserveOracle1.setExchangeRate(stateArgs.exchangeRate.toUint72());
        // keeper
        liquidate(keeper1, ilkIndex, borrower1);

        if (results.category == 0) {
            // protocol
            vm.writeLine("fuzz_out.txt", "PROTOCOL");
            assert(ionPool.collateral(ilkIndex, borrower1) == 0);
            assert(ionPool.normalizedDebt(ilkIndex, borrower1) == 0);
        } else if (results.category == 1) {
            // dust
            // assert(false); // to see if it's ever reaching this branch
            // ffi to see when this branch gets hit
            vm.writeLine("fuzz_out.txt", "DUST");
            assert(ionPool.normalizedDebt(ilkIndex, borrower1) == 0);
        } else if (results.category == 2) {
            vm.writeLine("fuzz_out.txt", "PARTIAL");
            uint256 actualCollateral = ionPool.collateral(ilkIndex, borrower1);
            console.log("actualCollateral: ", actualCollateral);
            uint256 actualNormalizedDebt = ionPool.normalizedDebt(ilkIndex, borrower1);
            if (actualNormalizedDebt != 0) {
                // Could be full liquidation if there was only 1 normalizedDebt in the beginning
                uint256 healthRatio = getHealthRatio(
                    actualCollateral,
                    actualNormalizedDebt,
                    stateArgs.rate,
                    stateArgs.exchangeRate,
                    deploymentArgs.liquidationThreshold
                );
                console.log("health ratio: ", healthRatio);
                assert(healthRatio >= deploymentArgs.targetHealth);
            }
        }
    }

    function testFuzz_ProtocolLiquidations(uint256 depositAmt, uint256 borrowAmt, uint256 exchangeRate) public {
        // state args
        StateArgs memory stateArgs;
        stateArgs.collateral = bound(depositAmt, minDepositAmt, maxDepositAmt);
        stateArgs.normalizedDebt = bound(borrowAmt, minDepositAmt, maxDepositAmt);
        stateArgs.exchangeRate = bound(exchangeRate, minExchangeRate, startingExchangeRate); // [wad]
        stateArgs.rate = NO_RATE;

        // starting position must be safe
        // [wad] * [ray] <= [wad] * [ray]
        vm.assume(
            stateArgs.normalizedDebt * stateArgs.rate
                <= (stateArgs.collateral * startingExchangeRate.scaleUpToRay(18)).rayMulDown(
                    deploymentArgs.liquidationThreshold
                )
        );

        // position needs to be unsafe after exchange rate change
        vm.assume(
            stateArgs.normalizedDebt * stateArgs.rate
                > (stateArgs.collateral * stateArgs.exchangeRate.scaleUpToRay(18)).rayMulDown(
                    deploymentArgs.liquidationThreshold
                )
        );

        Results memory results = calculateExpectedLiquidationResults(deploymentArgs, stateArgs);
        vm.assume(results.category == 0); // protocol liquidation

        // liquidations contract
        uint256[ILK_COUNT] memory liquidationThresholds = [deploymentArgs.liquidationThreshold, 0, 0, 0, 0, 0, 0, 0];
        liquidation = new Liquidation(
            address(ionPool), 
            revenueRecipient, 
            protocol,
            exchangeRateOracles, 
            liquidationThresholds, 
            deploymentArgs.targetHealth, 
            deploymentArgs.reserveFactor, 
            deploymentArgs.maxDiscount
        );
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // lender
        supply(lender1, stateArgs.normalizedDebt);
        // borrower makes a SAFE position
        borrow(borrower1, ilkIndex, stateArgs.collateral, stateArgs.normalizedDebt);
        // exchange rate changes based on fuzz
        reserveOracle1.setExchangeRate(stateArgs.exchangeRate.toUint72());
        // keeper
        liquidate(keeper1, ilkIndex, borrower1);

        // protocol liquidation should result in confiscating the entire position to the protocol
        assert(ionPool.collateral(ilkIndex, borrower1) == 0);
        assert(ionPool.normalizedDebt(ilkIndex, borrower1) == 0);
        assert(ionPool.gem(ilkIndex, protocol) == stateArgs.collateral);
        assert(ionPool.unbackedDebt(protocol) == stateArgs.normalizedDebt * stateArgs.rate);
    }

    // fuzz collateral value, liability value
    // 1)
    // safe: normalizedDebt * rate <= collateral * exchangeRate * liquidationThreshold
    // liabilityValue <= collateralValue
    // if liabilityValue > collateralValue, then bound liabilityValue between 0 and collateralValue
    // unsafe: liabilityValue > collateralValue
    //
    // fuzz collateral
    // safe bound = normalizedDebt = bound(0, collateral * exchangeRate * liquidationThreshold / rate)

    // unsafe bound = liabilityValue > collateralValue
    // normalizedDebt * rate > collateral * exchangeRate * liquidationThreshold
    // normalizedDebt * rate / collateral / liquidationthreshold > exchangeRate
    // exchangeRate = bound(0, normalizedDebt * rate / collateral / liquidationthreshold)
    //
    // unsafe
    // er = 2
    // lq = 0.9 ray
    //
    function testFuzz_PartialLiquidations(uint256 depositAmt, uint256 borrowAmt, uint256 exchangeRate) public {
        // state args
        StateArgs memory stateArgs;
        stateArgs.collateral = bound(depositAmt, minDepositAmt, maxDepositAmt);
        stateArgs.rate = NO_RATE;

        // starting position must be safe
        stateArgs.normalizedDebt = bound(
            borrowAmt,
            1,
            (stateArgs.collateral * startingExchangeRate.scaleUpToRay(18)).rayMulDown(
                deploymentArgs.liquidationThreshold
            ) / stateArgs.rate
        ); // [wad]
        // position must be unsafe after exchange rate change
        stateArgs.exchangeRate = bound(
            exchangeRate,
            minExchangeRate,
            (stateArgs.normalizedDebt * stateArgs.rate).rayDivDown(deploymentArgs.liquidationThreshold)
                / stateArgs.collateral - 1
        ); // [ray]
        // cast exchangeRate back to [wad]
        stateArgs.exchangeRate = stateArgs.exchangeRate.scaleDownToWad(27);

        vm.assume(stateArgs.exchangeRate > 0); // throw away output if exchangeRate is zero

        Results memory results = calculateExpectedLiquidationResults(deploymentArgs, stateArgs);
        vm.assume(results.category == 2); // partial liquidation

        // liquidations contract
        uint256[ILK_COUNT] memory liquidationThresholds = [deploymentArgs.liquidationThreshold, 0, 0, 0, 0, 0, 0, 0];
        liquidation = new Liquidation(
            address(ionPool), 
            revenueRecipient, 
            protocol,
            exchangeRateOracles, 
            liquidationThresholds, 
            deploymentArgs.targetHealth, 
            deploymentArgs.reserveFactor, 
            deploymentArgs.maxDiscount
        );
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // lender
        supply(lender1, stateArgs.normalizedDebt);
        // borrower makes a SAFE position
        borrow(borrower1, ilkIndex, stateArgs.collateral, stateArgs.normalizedDebt);
        // exchange rate changes based on fuzz
        reserveOracle1.setExchangeRate(stateArgs.exchangeRate.toUint72());
        // keeper
        liquidate(keeper1, ilkIndex, borrower1);

        // partial liquidation should result in the vault going up to target health ratio
        uint256 actualCollateral = ionPool.collateral(ilkIndex, borrower1);
        uint256 actualNormalizedDebt = ionPool.normalizedDebt(ilkIndex, borrower1);

        vm.assume(actualNormalizedDebt > 0); // throw away if debt was fully liquidated (possible if dust is zero)

        uint256 healthRatio = getHealthRatio(
            actualCollateral,
            actualNormalizedDebt,
            stateArgs.rate,
            stateArgs.exchangeRate,
            deploymentArgs.liquidationThreshold
        );
        assert(healthRatio >= deploymentArgs.targetHealth);
    }

    function testFuzz_DustLiquidations(uint256 depositAmt, uint256 borrowAmt, uint256 exchangeRate) public {
        // state args
        StateArgs memory stateArgs;
        stateArgs.collateral = bound(depositAmt, minDepositAmt, maxDepositAmt);
        stateArgs.rate = NO_RATE;

        // starting position must be safe
        stateArgs.normalizedDebt = bound(
            borrowAmt,
            1,
            (stateArgs.collateral * startingExchangeRate.scaleUpToRay(18)).rayMulDown(
                deploymentArgs.liquidationThreshold
            ) / stateArgs.rate
        ); // [wad]
        // position must be unsafe after exchange rate change
        stateArgs.exchangeRate = bound(
            exchangeRate,
            minExchangeRate,
            (stateArgs.normalizedDebt * stateArgs.rate).rayDivDown(deploymentArgs.liquidationThreshold)
                / stateArgs.collateral - 1
        ); // [ray]
        // cast exchangeRate back to [wad]
        stateArgs.exchangeRate = stateArgs.exchangeRate.scaleDownToWad(27);

        vm.assume(stateArgs.exchangeRate > 0); // throw away output if exchangeRate is zero

        Results memory results = calculateExpectedLiquidationResults(deploymentArgs, stateArgs);
        vm.assume(results.category == 1); // dust liquidation

        // liquidations contract
        uint256[ILK_COUNT] memory liquidationThresholds = [deploymentArgs.liquidationThreshold, 0, 0, 0, 0, 0, 0, 0];
        liquidation = new Liquidation(
            address(ionPool), 
            revenueRecipient, 
            protocol,
            exchangeRateOracles, 
            liquidationThresholds, 
            deploymentArgs.targetHealth, 
            deploymentArgs.reserveFactor, 
            deploymentArgs.maxDiscount
        );
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // lender
        supply(lender1, stateArgs.normalizedDebt);
        // borrower makes a SAFE position
        borrow(borrower1, ilkIndex, stateArgs.collateral, stateArgs.normalizedDebt);
        // exchange rate changes based on fuzz
        reserveOracle1.setExchangeRate(stateArgs.exchangeRate.toUint72());
        // keeper
        liquidate(keeper1, ilkIndex, borrower1);

        // dust liquidations should result in zero debt
        uint256 actualNormalizedDebt = ionPool.normalizedDebt(ilkIndex, borrower1);

        assert(actualNormalizedDebt == 0);
    }

    // resulting target health can be extremely high with miniscule debt amounts
    // function testFuzz_PartialCaseResultingTargetHealthRatioBound(

    // ) public {

    // }
    // function testFuzz_PartialLiquidationToTargetHealthRatioFuzzedRate(
    //     uint256 exchangeRate,
    //     uint256 depositAmt,
    //     uint256 borrowAmt,
    //     uint256 rate
    // ) public {

    // }
}

// contract LiquidationFuzzBoundedConfigs is LiquidationSharedSetup {

// }

// contract LiquidationFuzzTest is LiquidationSharedSetup {
//     using WadRayMath for uint256;

//     address constant REVENUE_RECIPIENT = address(1);
//     address constant BORROWER = address(2);
//     address constant LENDER = address(3);
//     address constant KEEPER = address(4);
//     uint8 constant ilkIndex = 0;

//     function getHealthRatio() public view { }

//     // function testFuzz_GemOutAndRepay(

//     // ) external {

//     // }

//     function testFuzz_CheckAllAssertsFixedConfigsNoRate(
//         uint256 exchangeRate,
//         uint256 depositAmt,
//         uint256 borrowAmt
//     )
//         external
//     {
//         LiquidationArgs memory args;

//         // configs
//         uint256 startingExchangeRate = 1 ether;

//         depositAmt = bound(depositAmt, 1 ether, 100 ether);
//         borrowAmt = bound(borrowAmt, 1 ether, 100 ether);
//         exchangeRate = bound(exchangeRate, 1, startingExchangeRate); // exchangeRate < startingExchangeRate

//         args.targetHealth = 1.25 ether;
//         args.liquidationThreshold = 0.8 ether;
//         args.maxDiscount = 0.2 ether;
//         args.reserveFactor = 0;

//         args.collateral = depositAmt;
//         args.exchangeRate = exchangeRate;
//         args.normalizedDebt = borrowAmt; // No rate
//         args.rate = 1 * RAY;

//         // starting position must be safe
//         vm.assume(borrowAmt * WAD / depositAmt < args.liquidationThreshold);

//         // new exchangeRate needs to result in healthRatio < 1

//         vm.assume(depositAmt * exchangeRate / WAD * args.liquidationThreshold / borrowAmt < 1 ether);

//         // expected results
//         Results memory results = calculateExpectedLiquidationResults(args);

//         // constrain exchangeRate to make vault unsafe
//         // [wad] * [wad] / [wad] * [wad] / [wad] = [wad]
//         // vm.assume(depositAmt * exchangeRate / WAD * args.liquidationThreshold / borrowAmt < 1 ether);

//         // instantiate liquidations contract
//         uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
//         liquidation = new Liquidation(
//             address(ionPool),
//             REVENUE_RECIPIENT,
//             exchangeRateOracles,
//             liquidationThresholds,
//             args.targetHealth,
//             args.reserveFactor,
//             args.maxDiscount
//         );
//         ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

//         // lender
//         supply(LENDER, borrowAmt);
//         // borrower makes a SAFE position
//         borrow(BORROWER, ilkIndex, depositAmt, borrowAmt);

//         // exchangeRate changes based on fuzz
//         reserveOracle1.setExchangeRate(exchangeRate);

//         // keeper
//         liquidate(KEEPER, ilkIndex, BORROWER);
//     }

//     function testFuzz_PartialLiquidationFixedConfigsNoRate(
//         uint256 exchangeRate,
//         uint256 depositamt,
//         uint256 borrowAmt
//     ) public {
//         LiquidationArgs memory args;

//         // liquidation configs
//         args.targetHealth = 1.25 ether;
//         args.liquidationThreshold = 0.8 ether;
//         args.maxDiscount = 0.2 ether;
//         args.reserveFactor = 0;

//         // partial liquidations occur if it's possible to get to targetHealthRatio
//     }

//     function testFuzz_ProtocolLiquidationFixedConfigsNoRate(
//         uint256 exchangeRate,
//         uint256 depositAmt,
//         uint256 borrowAmt
//     )
//         public
//     {
//         LiquidationArgs memory args;
//         // protocol liquidations occur in cases of bad debt
//         // if (gemOut > collateral) then (repay == normalizedDebt * rate)

//         uint256 startingExchangeRate = 1 ether;

//         depositAmt = bound(depositAmt, 1 ether, 100 ether);
//         borrowAmt = bound(borrowAmt, 1 ether, 100 ether);
//         exchangeRate = bound(exchangeRate, 1, startingExchangeRate);

//         args.targetHealth = 1.25 ether;
//         args.liquidationThreshold = 0.8 ether;
//         args.maxDiscount = 0.2 ether;
//         args.reserveFactor = 0;

//         args.collateral = depositAmt;
//         args.exchangeRate = exchangeRate;
//         args.normalizedDebt = borrowAmt;
//         args.rate = 1 * RAY;

//         // starting position must be safe
//         vm.assume(borrowAmt * WAD / depositAmt < args.liquidationThreshold);

//         // to avoid overflow in calculateExpectedLiquidationResults, healthRatio must be less than 1
//         vm.assume(depositAmt * exchangeRate / WAD * args.liquidationThreshold / borrowAmt < 1 ether);

//         // should generate bad debt
//         Results memory results = calculateExpectedLiquidationResults(args);
//         results.gemOut = results.gemOut.scaleToWad(27);
//         results.repay = results.repay.scaleToWad(27);

//         vm.assume(results.gemOut >= depositAmt);
//         vm.assume(results.repay > borrowAmt); // NOTE: actual condition being checked in liquidations

//         uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
//         liquidation = new Liquidation(
//             address(ionPool),
//             REVENUE_RECIPIENT,
//             exchangeRateOracles,
//             liquidationThresholds,
//             args.targetHealth,
//             args.reserveFactor,
//             args.maxDiscount
//         );
//         ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

//         // lender
//         supply(LENDER, borrowAmt);

//         // borrower makes a SAFE position
//         borrow(BORROWER, ilkIndex, depositAmt, borrowAmt);

//         // exchangeRate changes based on fuzz
//         reserveOracle1.setExchangeRate(exchangeRate);

//         // keeper
//         liquidate(KEEPER, ilkIndex, BORROWER);

//         // results
//         // if bad debt => protocol confiscates, resulting normalized and collateral is both zero
//         assert(ionPool.collateral(ilkIndex, BORROWER) == 0);
//         assert(ionPool.normalizedDebt(ilkIndex, BORROWER) == 0);
//     }

//     function testFuzz_DustLiquidationFixedConfigsNoRate(
//         uint256 exchangeRate,
//         uint256 depositAmt,
//         uint256 borrowAmt
//     )
//         public
//     {
//         LiquidationArgs memory args;
//         uint256 startingExchangeRate = 1 ether;

//         // update dust
//         ionPool.updateIlkDust(ilkIndex, uint256(0.5 ether).scaleToRad(18)); // [rad]
//         uint256 dust = ionPool.dust(ilkIndex);

//         depositAmt = bound(depositAmt, 1 ether, 100 ether);
//         borrowAmt = bound(borrowAmt, dust.scaleToWad(45), 100 ether); // dust is minimum borrow
//         exchangeRate = bound(exchangeRate, 1, startingExchangeRate);

//         args.targetHealth = 1.25 ether;
//         args.liquidationThreshold = 0.8 ether;
//         args.maxDiscount = 0.2 ether;
//         args.reserveFactor = 0;

//         args.collateral = depositAmt;
//         args.exchangeRate = exchangeRate;
//         args.normalizedDebt = borrowAmt;
//         args.rate = 1 * RAY;

//         // starting position must be safe
//         vm.assume(borrowAmt * WAD / depositAmt < args.liquidationThreshold);

//         // to avoid overflow in calculateExpectedLiquidationResults, healthRatio must be less than 1
//         vm.assume(depositAmt * exchangeRate / WAD * args.liquidationThreshold / borrowAmt < 1 ether);

//         // expected results
//         Results memory results = calculateExpectedLiquidationResults(args);
//         results.gemOut = results.gemOut.scaleToWad(27);
//         results.repay = results.repay.scaleToWad(27);

//         // should not be a protocol liquidation (i.e. no bad debt)
//         vm.assume(results.repay <= borrowAmt);
//         vm.assume(results.gemOut <= depositAmt);

//         // but should leave dust
//         vm.assume(borrowAmt * args.rate - results.repay.scaleToRad(18) < dust);

//         // actions
//         uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
//         liquidation = new Liquidation(
//             address(ionPool),
//             REVENUE_RECIPIENT,
//             exchangeRateOracles,
//             liquidationThresholds,
//             args.targetHealth,
//             args.reserveFactor,
//             args.maxDiscount
//         );
//         ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

//         // lender
//         supply(LENDER, borrowAmt);

//         // borrower makes a SAFE position
//         borrow(BORROWER, ilkIndex, depositAmt, borrowAmt);

//         // exchangeRate changes based on fuzz
//         reserveOracle1.setExchangeRate(exchangeRate);

//         // keeper
//         liquidate(KEEPER, ilkIndex, BORROWER);

//         // results
//         assert(ionPool.normalizedDebt(ilkIndex, BORROWER) == 0);
//     }

//     function testFuzz_FuzzAllVariablesForAllOutcomesWithRate() public {
//         // bound each variable to realistic numberes
//         // if partial liquidation then assert
//         // if dust lquidation then assert
//         // if protocol liquidation then assert
//     }
// }
