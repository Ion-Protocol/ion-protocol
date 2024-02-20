// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LiquidationSharedSetup } from "../../helpers/LiquidationSharedSetup.sol";
import { WadRayMath } from "../../../src/libraries/math/WadRayMath.sol";
import { Liquidation } from "../../../src/Liquidation.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * Fixes deployment configs and fuzzes potential states
 */
contract LiquidationFuzzFixedConfigs is LiquidationSharedSetup {
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
    uint256 constant DUST_PERCENTAGE = 10; // percentage of total debt to be configured as dust

    function setUp() public override {
        super.setUp();

        // default configs
        deploymentArgs.targetHealth = 1.25e27; // [ray]
        deploymentArgs.reserveFactor = 0.02e27; // [ray]
        deploymentArgs.maxDiscount = 0.2e27; // [ray]
        deploymentArgs.liquidationThreshold = 0.9e27; // [ray]

        // fuzz configs
        minDepositAmt = 1e18;
        maxDepositAmt = 10_000e18;
        minBorrowAmt = 1;
        maxBorrowAmt = 10_000e18;
        minExchangeRate = 1; // overflows if zero because collateral value becomes zero
        startingExchangeRate = 1e18;
    }

    // runs 10,000 allowed misses 10,000
    function testFuzz_AllLiquidationCategoriesWithRate(
        uint104 depositAmt,
        uint104 borrowAmt,
        uint256 exchangeRate,
        uint104 rate
    )
        public
    {
        // state args
        stateArgs.collateral = bound(depositAmt, minDepositAmt, maxDepositAmt);
        stateArgs.rate = bound(rate, NO_RATE, type(uint104).max);

        ionPool.setRate(ILK_INDEX, uint104(stateArgs.rate));

        // starting position must be safe
        maxBorrowAmt = (stateArgs.collateral * startingExchangeRate.scaleUpToRay(18)).rayMulDown(
            deploymentArgs.liquidationThreshold
        ) / stateArgs.rate;
        minBorrowAmt = maxBorrowAmt < minBorrowAmt ? maxBorrowAmt : minBorrowAmt;

        stateArgs.normalizedDebt = bound(borrowAmt, minBorrowAmt, maxBorrowAmt); // [wad]

        vm.assume(stateArgs.normalizedDebt != 0); // if normalizedDebt is zero, position cannot become unsafe afterwards

        // position must be unsafe after exchange rate change
        maxExchangeRate = (stateArgs.normalizedDebt * stateArgs.rate).rayDivDown(deploymentArgs.liquidationThreshold)
            / stateArgs.collateral;
        vm.assume(maxExchangeRate != 0);
        maxExchangeRate = maxExchangeRate - 1;
        minExchangeRate = maxExchangeRate < minExchangeRate ? maxExchangeRate : minExchangeRate;

        stateArgs.exchangeRate = bound(
            exchangeRate,
            minExchangeRate, // if 1, max can be lower than min and it will fail
            maxExchangeRate
        ); // [ray] if the debt is zero, then there is no

        stateArgs.exchangeRate = stateArgs.exchangeRate.scaleDownToWad(27);
        vm.assume(stateArgs.exchangeRate > 0);

        // dust is set to a % of total debt
        deploymentArgs.dust = stateArgs.normalizedDebt * stateArgs.rate / DUST_PERCENTAGE; // [rad]
        ionPool.updateIlkDust(ILK_INDEX, deploymentArgs.dust);

        liquidation = new Liquidation(
            address(ionPool),
            protocol,
            exchangeRateOracles[0],
            deploymentArgs.liquidationThreshold,
            deploymentArgs.targetHealth,
            deploymentArgs.reserveFactor,
            deploymentArgs.maxDiscount
        );
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        Results memory results = calculateExpectedLiquidationResults(deploymentArgs, stateArgs);

        // lender
        uint256 supplyAmt = stateArgs.normalizedDebt * stateArgs.rate / RAY + 1;
        supply(lender1, supplyAmt);
        // borrower makes a SAFE position
        borrow(borrower1, ILK_INDEX, stateArgs.collateral, stateArgs.normalizedDebt);
        // exchange rate changes based on fuzz
        reserveOracle1.setExchangeRate(stateArgs.exchangeRate.toUint72());
        // keeper
        liquidate(keeper1, ILK_INDEX, borrower1);

        if (results.category == 0) {
            // protocol
            // vm.writeLine("fuzz_out.txt", "PROTOCOL");
            assert(ionPool.collateral(ILK_INDEX, borrower1) == 0);
            assert(ionPool.normalizedDebt(ILK_INDEX, borrower1) == 0);
        } else if (results.category == 1) {
            // dust
            // assert(false); // to see if it's ever reaching this branch
            // ffi to see when this branch gets hit
            // vm.writeLine("fuzz_out.txt", "DUST");
            assert(ionPool.normalizedDebt(ILK_INDEX, borrower1) == 0);
            assert(ionPool.unbackedDebt(address(liquidation)) == 0);
        } else if (results.category == 2) {
            // vm.writeLine("fuzz_out.txt", "PARTIAL");
            uint256 actualCollateral = ionPool.collateral(ILK_INDEX, borrower1);
            uint256 actualNormalizedDebt = ionPool.normalizedDebt(ILK_INDEX, borrower1);
            if (actualNormalizedDebt != 0) {
                // Could be full liquidation if there was only 1 normalizedDebt in the beginning
                uint256 healthRatio = getHealthRatio(
                    actualCollateral,
                    actualNormalizedDebt,
                    stateArgs.rate,
                    stateArgs.exchangeRate,
                    deploymentArgs.liquidationThreshold
                );
                assert(healthRatio >= deploymentArgs.targetHealth);
                assert(ionPool.unbackedDebt(address(liquidation)) == 0);
            }
        }
    }

    /**
     * Checks all possible liquidation outcomes.
     * NOTE: runs = 100,000 max_test_rejects = 100,000
     */
    function testFuzz_AllLiquidationCategoriesNoRate(
        uint256 depositAmt,
        uint256 borrowAmt,
        uint256 exchangeRate
    )
        public
    {
        // state args
        stateArgs.collateral = bound(depositAmt, minDepositAmt, maxDepositAmt);
        stateArgs.rate = NO_RATE;

        // starting position must be safe
        maxBorrowAmt = (stateArgs.collateral * startingExchangeRate.scaleUpToRay(18)).rayMulDown(
            deploymentArgs.liquidationThreshold
        ) / stateArgs.rate;
        minBorrowAmt = maxBorrowAmt < minBorrowAmt ? maxBorrowAmt : minBorrowAmt;

        stateArgs.normalizedDebt = bound(borrowAmt, minBorrowAmt, maxBorrowAmt); // [wad]
        vm.assume(stateArgs.normalizedDebt != 0); // if normalizedDebt is zero, position cannot become unsafe afterwards

        // position must be unsafe after exchange rate change
        maxExchangeRate = (stateArgs.normalizedDebt * stateArgs.rate).rayDivDown(deploymentArgs.liquidationThreshold)
            / stateArgs.collateral - 1;
        minExchangeRate = maxExchangeRate < minExchangeRate ? maxExchangeRate : minExchangeRate;

        stateArgs.exchangeRate = bound(
            exchangeRate,
            minExchangeRate, // if 1, max can be lower than min and it will fail
            maxExchangeRate
        ); // [ray] if the debt is zero, then there is no

        stateArgs.exchangeRate = stateArgs.exchangeRate.scaleDownToWad(27);
        vm.assume(stateArgs.exchangeRate > 0);

        // dust is set to 10% of total debt
        deploymentArgs.dust = stateArgs.normalizedDebt * stateArgs.rate / DUST_PERCENTAGE; // [rad]
        ionPool.updateIlkDust(ILK_INDEX, deploymentArgs.dust);

        liquidation = new Liquidation(
            address(ionPool),
            protocol,
            exchangeRateOracles[0],
            deploymentArgs.liquidationThreshold,
            deploymentArgs.targetHealth,
            deploymentArgs.reserveFactor,
            deploymentArgs.maxDiscount
        );
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        Results memory results = calculateExpectedLiquidationResults(deploymentArgs, stateArgs);

        // lender
        supply(lender1, stateArgs.normalizedDebt);
        // borrower makes a SAFE position
        borrow(borrower1, ILK_INDEX, stateArgs.collateral, stateArgs.normalizedDebt);
        // exchange rate changes based on fuzz
        reserveOracle1.setExchangeRate(stateArgs.exchangeRate.toUint72());
        // keeper
        liquidate(keeper1, ILK_INDEX, borrower1);

        if (results.category == 0) {
            // protocol
            // vm.writeLine("fuzz_out.txt", "PROTOCOL");
            assert(ionPool.collateral(ILK_INDEX, borrower1) == 0);
            assert(ionPool.normalizedDebt(ILK_INDEX, borrower1) == 0);
        } else if (results.category == 1) {
            // dust
            // assert(false); // to see if it's ever reaching this branch
            // ffi to see when this branch gets hit
            // vm.writeLine("fuzz_out.txt", "DUST");
            assert(ionPool.normalizedDebt(ILK_INDEX, borrower1) == 0);
        } else if (results.category == 2) {
            // vm.writeLine("fuzz_out.txt", "PARTIAL");
            uint256 actualCollateral = ionPool.collateral(ILK_INDEX, borrower1);
            uint256 actualNormalizedDebt = ionPool.normalizedDebt(ILK_INDEX, borrower1);
            if (actualNormalizedDebt != 0) {
                // Could be full liquidation if there was only 1 normalizedDebt in the beginning
                uint256 healthRatio = getHealthRatio(
                    actualCollateral,
                    actualNormalizedDebt,
                    stateArgs.rate,
                    stateArgs.exchangeRate,
                    deploymentArgs.liquidationThreshold
                );
                assert(healthRatio >= deploymentArgs.targetHealth);
            }
        }
    }
}
