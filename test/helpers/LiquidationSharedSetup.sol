// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { IonPoolSharedSetup } from "../helpers/IonPoolSharedSetup.sol";
import { Liquidation } from "src/Liquidation.sol";
import { GemJoin } from "src/join/GemJoin.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import "forge-std/console.sol";

contract MockReserveOracle {
    uint256 public exchangeRate;

    function setExchangeRate(uint256 _exchangeRate) public {
        exchangeRate = _exchangeRate;
    }

    // @dev called by Liquidation.sol
    function getExchangeRate() public returns (uint256) {
        return exchangeRate;
    }
}

contract LiquidationSharedSetup is IonPoolSharedSetup {
    using RoundedMath for uint256;

    uint256 constant WAD = 1e18;
    uint256 constant RAY = 1e27;

    uint32 constant ILK_COUNT = 8;

    Liquidation public liquidation;
    GemJoin public gemJoin;

    MockReserveOracle public reserveOracle1;
    MockReserveOracle public reserveOracle2;
    MockReserveOracle public reserveOracle3;

    address[] public exchangeRateOracles;

    uint8 public ilkIndex;

    address immutable keeper1 = vm.addr(99);
    address immutable revenueRecipient = vm.addr(100);

    struct LiquidationArgs {
        uint256 collateral;
        uint256 liquidationThreshold;
        uint256 exchangeRate;
        uint256 normalizedDebt;
        uint256 rate;
        uint256 targetHealth;
        uint256 reserveFactor;
        uint256 maxDiscount;
    }

    function setUp() public override {
        super.setUp();

        ilkIndex = 0;

        // set debt ceiling
        ionPool.updateIlkDebtCeiling(ilkIndex, uint256(int256(-1)));

        // create supply position
        supply(lender1, 100 ether);

        // TODO: Make ReserveOracleSharedSetUp
        reserveOracle1 = new MockReserveOracle();
        reserveOracle2 = new MockReserveOracle();
        reserveOracle3 = new MockReserveOracle();

        exchangeRateOracles = [
            address(reserveOracle1),
            address(reserveOracle2),
            address(reserveOracle3),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0)
        ];
    }

    /**
     * @dev Converts percentage to WAD. Used for instantiating liquidationThreshold arrays
     * @param percentages number out of 100 ex) 75 input will return
     */
    function getPercentageInWad(uint8[ILK_COUNT] memory percentages) internal returns (uint64[] memory results) {
        for (uint8 i = 0; i < ILK_COUNT; i++) {
            results[i] = uint64((uint256(percentages[i]) * WAD) / 100);
        }
    }

    /**
     * @dev Helper function to create supply positions. Approves and calls Supply
     */
    function supply(address lender, uint256 supplyAmt) internal {
        underlying.mint(lender, supplyAmt);
        vm.startPrank(lender);
        underlying.approve(address(ionPool), supplyAmt);
        ionPool.supply(lender, supplyAmt, new bytes32[](0));
        vm.stopPrank();
    }

    /**
     * @dev Helper function to create borrow positions. Call gemJoin and modifyPosition.
     * NOTE: does not normalize. Assumes the rate is 1.
     */
    function borrow(address borrower, uint8 ilkIndex, uint256 depositAmt, uint256 borrowAmt) internal {
        // mint
        mintableCollaterals[ilkIndex].mint(borrower, depositAmt);
        vm.startPrank(borrower);
        // join
        gemJoin = gemJoins[ilkIndex];
        mintableCollaterals[ilkIndex].approve(address(gemJoin), depositAmt);
        gemJoin.join(borrower, depositAmt);
        // move collateral to vault
        ionPool.moveGemToVault(ilkIndex, borrower, borrower, depositAmt, emptyProof);
        ionPool.borrow(ilkIndex, borrower, borrower, borrowAmt, emptyProof);
        vm.stopPrank();
    }

    function liquidate(address keeper, uint8 ilkIndex, address vault) internal {
        uint256 totalDebt = ionPool.normalizedDebt(ilkIndex, vault).rayMulUp(ionPool.rate(ilkIndex)); // [wad]
        underlying.mint(keeper, totalDebt); // mint enough to fully liquidate just in case
        vm.startPrank(keeper);
        underlying.approve(address(liquidation), totalDebt);
        liquidation.liquidate(ilkIndex, vault, keeper);
        vm.stopPrank();
    }

    function fundEth(address usr, uint256 amount) public {
        underlying.mint(usr, amount);
        vm.startPrank(usr);

        vm.stopPrank();
    }

    /**
     * Helper function to calculate the resulting collateral and debt after a successful partial liquidation
     * Keeps excess amount of precision in intermediate calculations.
     * NOTE: should not be used when testing full liquidation scenarios
     */
    struct Results {
        uint256 collateral;
        uint256 normalizedDebt;
        uint256 gemOut;
        uint256 repay;
    }

    function calculateExpectedLiquidationResults(LiquidationArgs memory _args)
        internal
        view
        returns (Results memory results)
    {
        console.log("--- calculate expected results --- ");
        LiquidationArgs memory args;

        // give every variable more precision during the calculation
        args.collateral = _args.collateral.scaleToRay(18);
        args.liquidationThreshold = _args.liquidationThreshold.scaleToRay(18);
        args.exchangeRate = _args.exchangeRate.scaleToRay(18);
        args.normalizedDebt = _args.normalizedDebt.scaleToRay(18);
        args.rate = _args.rate;
        args.targetHealth = _args.targetHealth.scaleToRay(18);
        args.reserveFactor = _args.reserveFactor.scaleToRay(18);
        args.maxDiscount = _args.maxDiscount.scaleToRay(18);

        console.log("args.collateral: ", args.collateral);
        console.log("args.liquidationThreshold: ", args.liquidationThreshold);
        console.log("args.exchangeRate: ", args.exchangeRate);
        console.log("args.normalizedDebt: ", args.normalizedDebt);
        console.log("args.targetHealth: ", args.targetHealth);
        console.log("args.reserveFactor: ", args.reserveFactor);
        console.log("args.maxDiscount: ", args.maxDiscount);

        uint256 collateralValue = (((args.collateral * args.liquidationThreshold) / RAY) * args.exchangeRate) / RAY; // [ray]
        console.log("collateralValue: ", collateralValue);

        uint256 liabilityValue = (args.rate * args.normalizedDebt) / RAY; // [ray]
        console.log("liabilityValue: ", liabilityValue);

        uint256 healthRatio = (collateralValue * RAY) / liabilityValue; // [ray]
        console.log("healthRatio: ", healthRatio);

        uint256 discount = args.reserveFactor + (RAY - healthRatio); // [ray]
        discount = discount <= args.maxDiscount ? discount : args.maxDiscount; // [ray]
        console.log("discount: ", discount);

        uint256 repayNum = (args.targetHealth * liabilityValue) / (RAY) - collateralValue; // [ray]
        console.log("repayNum: ", repayNum);

        uint256 repayDen = args.targetHealth - (((args.liquidationThreshold) * RAY) / (RAY - discount)); // [ray]
        console.log("repayDen: ", repayDen);

        results.repay = (repayNum * RAY) / repayDen; // [ray]
        console.log("repay: ", results.repay);

        uint256 collateralSalePrice = (args.exchangeRate * (RAY - discount)) / RAY; // [ray] ETH / LST
        console.log("collateralSalePrice: ", collateralSalePrice);

        results.gemOut = (results.repay * RAY) / collateralSalePrice; // [ray]
        console.log("gemOut: ", results.gemOut);

        if (results.gemOut > args.collateral) {
            console.log("not enough collateral to sell");
        } else {
            console.log("gemOut <= collateral");
            results.collateral = args.collateral - results.gemOut; // [ray]
        }

        if (results.repay > liabilityValue) {
            console.log("repay greater than liabilityValue");
        } else {
            console.log("repay <= liabilityValue");
            results.normalizedDebt = ((liabilityValue - results.repay) * RAY) / args.rate; // [ray]
        }

        // both else statements above is true
        if (!(results.gemOut > args.collateral && results.repay > liabilityValue)) {
            uint256 resultingHealthRatio =
                results.collateral.roundedRayMul(args.exchangeRate).roundedRayMul(args.liquidationThreshold);
            console.log("col exchangeRate liqThreshold:", resultingHealthRatio);
            console.log("first div: ", resultingHealthRatio.roundedRayDiv(results.normalizedDebt));
            resultingHealthRatio = resultingHealthRatio.roundedRayDiv(results.normalizedDebt).roundedRayDiv(args.rate);
            console.log("resultingHealthRatio: ", resultingHealthRatio);
        }

        console.log("---");
    }

    // tests the helper function for calculating expected liquidation results
    /**
     * 100 ether deposit 50 ether borrow
     * mat is 0.5
     * exchangeRate is now 0.95
     * collateralValue = 0.5 * 0.95 * 100 = 47.5
     * healthRatio = collateral / debt = 47.5 / 50 = 0.95
     * discount = 0.02 + (1 - 0.5) = 0.07
     * repayNum = (1.25 * 50) - 47.5 = 15
     * repayDen = 1.25 - (0.5 / (1-0.07)) = 0.7123
     * repay = 21.05660377
     * gemOut = repay / (exchangeRate * (1 - discount)) =
     */
    function test_CalculateExpectedLiquidationResults() public {
        LiquidationArgs memory args;

        args.collateral = 100 ether; // [wad]
        args.liquidationThreshold = 0.5 ether; // [wad]
        args.exchangeRate = 0.95 ether;
        args.normalizedDebt = 50 ether; // [wad]
        args.rate = RAY; // [ray]
        args.targetHealth = 1.25 ether; // [wad]
        args.reserveFactor = 0.02 ether; // [wad]
        args.maxDiscount = 0.2 ether; // [wad]

        Results memory results = calculateExpectedLiquidationResults(args);
        console.log("resultingCollateral: ", results.collateral);
        console.log("resultingNormalizedDebt: ", results.normalizedDebt);
        assertEq(results.collateral, 76_166_832_174_776_564_051_638_530_294); // [ray]
        assertEq(results.normalizedDebt, 28_943_396_226_415_094_339_622_641_514); // [ray]
    }
}
