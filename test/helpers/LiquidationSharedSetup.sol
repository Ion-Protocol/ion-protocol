// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { IonPoolSharedSetup } from "../helpers/IonPoolSharedSetup.sol";
import { Liquidation } from "src/Liquidation.sol";
import { GemJoin } from "src/join/GemJoin.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";
import "forge-std/console.sol";

contract MockReserveOracle {
    uint72 public exchangeRate;

    function setExchangeRate(uint72 _exchangeRate) public {
        exchangeRate = _exchangeRate;
        console.log("set exchange rate: ", exchangeRate);
    }
}

contract LiquidationSharedSetup is IonPoolSharedSetup {
    using WadRayMath for uint256;

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
    address immutable protocol = vm.addr(101);

    struct StateArgs {
        uint256 collateral;
        uint256 exchangeRate;
        uint256 normalizedDebt;
        uint256 rate;
    }

    struct DeploymentArgs {
        uint256 liquidationThreshold;
        uint256 targetHealth;
        uint256 reserveFactor;
        uint256 maxDiscount;
        uint256 dust;
    }

    struct Results {
        uint256 collateral;
        uint256 normalizedDebt;
        uint256 gemOut;
        uint256 dart;
        uint256 repay;
        uint256 category;
    }

    function setUp() public virtual override {
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
    function getPercentageInWad(uint8[ILK_COUNT] memory percentages) internal pure returns (uint64[] memory results) {
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
        ionPool.depositCollateral(ilkIndex, borrower, borrower, depositAmt, emptyProof);
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
     * @dev Helper function to calculate the resulting health ratio of a vault.
     * Rounds everything to protocol's favor, making the users pay more to get to the targetHealthRatio.
     * (collateral * exchangeRate * liquidationThreshold) / (normalizedDebt * rate)
     */
    function getHealthRatio(
        uint256 collateral, // [wad]
        uint256 normalizedDebt, // [wad]
        uint256 rate, // [wad]
        uint256 exchangeRate, // [wad]
        uint256 liquidationThreshold // [ray]
    )
        internal
        pure
        returns (uint256 resultingHealthRatio)
    {
        exchangeRate = exchangeRate.scaleUpToRay(18);
        resultingHealthRatio = (collateral * exchangeRate).rayMulDown(liquidationThreshold);
        resultingHealthRatio = resultingHealthRatio.rayDivDown(normalizedDebt).rayDivDown(rate);
    }

    /**
     * @dev Helper function to calculate the resulting collateral and debt after a successful partial liquidation
     * Keeps excess amount of precision in intermediate calculations.
     * NOTE: should not be used when testing full liquidation scenarios
     */
    function calculateExpectedLiquidationResults(
        DeploymentArgs memory _dArgs,
        StateArgs memory _sArgs
    )
        internal
        view
        returns (Results memory results)
    {
        DeploymentArgs memory dArgs;
        StateArgs memory sArgs;
        // copy to new memory
        // scale exchangeRate to ray
        sArgs.exchangeRate = _sArgs.exchangeRate.scaleUpToRay(18);
        sArgs.collateral = _sArgs.collateral;
        sArgs.normalizedDebt = _sArgs.normalizedDebt;
        sArgs.rate = _sArgs.rate;

        dArgs.liquidationThreshold = _dArgs.liquidationThreshold;
        dArgs.targetHealth = _dArgs.targetHealth;
        dArgs.reserveFactor = _dArgs.reserveFactor;
        dArgs.maxDiscount = _dArgs.maxDiscount;
        dArgs.dust = _dArgs.dust;

        uint256 collateralValue = (sArgs.collateral * dArgs.liquidationThreshold).rayMulUp(sArgs.exchangeRate); // [rad]
        console.log("collateralValue: [rad] ", collateralValue);

        uint256 liabilityValue = (sArgs.rate * sArgs.normalizedDebt); // [rad]
        console.log("liabilityValue: [rad] ", liabilityValue);

        uint256 healthRatio = collateralValue.rayDivDown(liabilityValue); // [ray]
        console.log("healthRatio: ", healthRatio);

        uint256 discount = dArgs.reserveFactor + (RAY - healthRatio); // [ray]
        discount = discount <= dArgs.maxDiscount ? discount : dArgs.maxDiscount; // [ray]
        console.log("discount: ", discount);

        uint256 repayNum = liabilityValue.rayMulUp(dArgs.targetHealth) - collateralValue; // [rad] - [rad]
        console.log("repayNum: ", repayNum);

        uint256 repayDen = dArgs.targetHealth - dArgs.liquidationThreshold.rayDivUp(RAY - discount);
        console.log("repayDen: ", repayDen);

        results.repay = repayNum.rayDivUp(repayDen);
        console.log("repay: ", results.repay);

        uint256 collateralSalePrice = sArgs.exchangeRate.rayMulUp(RAY - discount);
        console.log("collateralSalePrice: ", collateralSalePrice);

        if (results.repay > liabilityValue) {
            console.log("protocol liquidation");
            // if repay > liabilityValue, then liabilityValue / collateralSalePrice > collateral
            console.log("liabilityValue / collateralSalePrice: ", liabilityValue / collateralSalePrice);
            console.log("sArgs.collateral: ", sArgs.collateral);
            assert(liabilityValue / collateralSalePrice >= sArgs.collateral);
            results.dart = sArgs.normalizedDebt;
            results.gemOut = sArgs.collateral;

            results.collateral = 0;
            results.normalizedDebt = 0;

            results.category = 0;
        } else if (liabilityValue - results.repay < dArgs.dust) {
            console.log("dust liquidation");
            console.log("dust: ", dArgs.dust);
            results.repay = liabilityValue;

            results.dart = sArgs.normalizedDebt;
            results.gemOut = liabilityValue / collateralSalePrice;

            results.collateral = sArgs.collateral - results.gemOut;
            results.normalizedDebt = 0;

            results.category = 1;
        } else if (liabilityValue - results.repay >= dArgs.dust) {
            console.log("PARTIAL LIQUIDATION");
            console.log("liabilityValue: ", liabilityValue);
            console.log("results.repay: ", results.repay);
            console.log("dArgs.dust: ", dArgs.dust);
            console.log("liabilityValue - results.repay: ", liabilityValue - results.repay);
            console.log("liabilityValue - results.repay < dArgs.dust", liabilityValue - results.repay < dArgs.dust);
            // results.repay unchanged
            results.dart = results.repay / sArgs.rate;
            console.log("results.dart: ", results.dart);
            results.dart = sArgs.rate * results.dart < results.repay ? results.dart + 1 : results.dart; // round up
            console.log("results.dart rounded: ", results.dart);
            results.gemOut = results.repay / collateralSalePrice;
            console.log("results.gemOut: ", results.gemOut);
            results.collateral = sArgs.collateral - results.gemOut;
            results.normalizedDebt = sArgs.normalizedDebt - results.dart;

            results.category = 2;
        } else {
            require(false, "panic"); // shouldn't occur
        }
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
    // function test_CalculateExpectedLiquidationResults() public {

    //     args.collateral = 100e18; // [wad]
    //     args.liquidationThreshold = 0.5e27; // [wad]
    //     args.exchangeRate = 0.95e18;
    //     args.normalizedDebt = 50e18; // [wad]
    //     args.rate = 1e27; // [ray]
    //     args.targetHealth = 1.25e27; // [wad]
    //     args.reserveFactor = 0.02e27; // [wad]
    //     args.maxDiscount = 0.2e27; // [wad]

    //     Results memory results = calculateExpectedLiquidationResults(args);
    //     console.log("resultingCollateral: ", results.collateral);
    //     console.log("resultingNormalizedDebt: ", results.normalizedDebt);
    //     assertEq(results.collateral, 76166832174776564052, "collateral"); // [ray]
    //     assertEq(results.normalizedDebt, 28943396226415094339, "normalizedDebt"); // [ray]
    // }
}
