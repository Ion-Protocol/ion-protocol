// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { IonPoolSharedSetup, MockReserveOracle } from "../helpers/IonPoolSharedSetup.sol";
import { Liquidation } from "src/Liquidation.sol";
import { GemJoin } from "src/join/GemJoin.sol";
import { WadRayMath } from "src/libraries/math/RoundedMath.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { console2 } from "forge-std/console2.sol";

contract LiquidationSharedSetup is IonPoolSharedSetup {
    using WadRayMath for uint256;
    using Math for uint256; 
    using Strings for uint256;
    using SafeCast for *; 

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

    error NegativeDiscriminant(int256 discriminant); 
    error NegativeIntercept(int256 intercept); 

    function setUp() public virtual override {
        super.setUp();

        ilkIndex = 0;

        // set debt ceiling
        ionPool.updateIlkDebtCeiling(ilkIndex, uint256(int256(-1)));

        // create supply position
        supply(lender1, 100 ether);

        // TODO: Make ReserveOracleSharedSetUp
        reserveOracle1 = new MockReserveOracle(0);
        reserveOracle2 = new MockReserveOracle(0);
        reserveOracle3 = new MockReserveOracle(0);

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
        uint256 rate, // [ray]
        uint256 exchangeRate, // [wad] but converted to ray during calculation
        uint256 liquidationThreshold // [ray]
    )
        internal
        pure
        returns (uint256 resultingHealthRatio)
    {
        exchangeRate = exchangeRate.scaleUpToRay(18);
        // [wad] * [ray] * [ray] / RAY = [rad] 
        resultingHealthRatio = (collateral * exchangeRate).rayMulDown(liquidationThreshold);
        // [rad] * RAY / [rad] = [ray] 
        resultingHealthRatio = resultingHealthRatio.rayDivDown(normalizedDebt * rate); 
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
        console2.log("--- calculate expected results --- ");

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

        console2.log("collateral: ", sArgs.collateral);
        console2.log("normalizedDebt: ", sArgs.normalizedDebt);
        console2.log("rate: ", sArgs.rate);
        console2.log("exchangeRate: ", sArgs.exchangeRate);

        console2.log("liquidationThreshold: ", dArgs.liquidationThreshold);
        console2.log("targetHealth: ", dArgs.targetHealth);
        console2.log("reserveFactor: ", dArgs.reserveFactor);
        console2.log("maxDiscount: ", dArgs.maxDiscount);
        console2.log("dust: ", dArgs.dust);

        uint256 collateralValue = (sArgs.collateral * dArgs.liquidationThreshold).rayMulUp(sArgs.exchangeRate); // [rad]
        console2.log("collateralValue: [rad] ", collateralValue);

        uint256 liabilityValue = (sArgs.rate * sArgs.normalizedDebt); // [rad]
        console2.log("liabilityValue: [rad] ", liabilityValue);

        uint256 healthRatio = collateralValue.rayDivDown(liabilityValue); // [ray]
        console2.log("healthRatio: ", healthRatio);

        uint256 discount = dArgs.reserveFactor + (RAY - healthRatio); // [ray]
        discount = discount <= dArgs.maxDiscount ? discount : dArgs.maxDiscount; // [ray]
        console2.log("discount: ", discount);

        uint256 repayNum = liabilityValue.rayMulUp(dArgs.targetHealth) - collateralValue; // [rad] - [rad]
        console2.log("repayNum: ", repayNum);

        uint256 repayDen = dArgs.targetHealth - dArgs.liquidationThreshold.rayDivUp(RAY - discount);
        console2.log("repayDen: ", repayDen);

        results.repay = repayNum.rayDivUp(repayDen);
        console2.log("repay: ", results.repay);

        uint256 collateralSalePrice = sArgs.exchangeRate.rayMulUp(RAY - discount);
        console2.log("collateralSalePrice: ", collateralSalePrice);

        if (results.repay > liabilityValue) {
            console2.log("protocol liquidation");
            // if repay > liabilityValue, then liabilityValue / collateralSalePrice > collateral
            console2.log("liabilityValue / collateralSalePrice: ", liabilityValue / collateralSalePrice);
            console2.log("sArgs.collateral: ", sArgs.collateral);
            assert(liabilityValue / collateralSalePrice >= sArgs.collateral);
            results.dart = sArgs.normalizedDebt;
            results.gemOut = sArgs.collateral;

            results.collateral = 0;
            results.normalizedDebt = 0;

            results.category = 0;
        } else if (liabilityValue - results.repay < dArgs.dust) {
            console2.log("dust liquidation");
            console2.log("dust: ", dArgs.dust);
            results.repay = liabilityValue;

            results.dart = sArgs.normalizedDebt;
            results.gemOut = liabilityValue / collateralSalePrice;

            results.collateral = sArgs.collateral - results.gemOut;
            results.normalizedDebt = 0;

            results.category = 1;
        } else if (liabilityValue - results.repay >= dArgs.dust) {
            console2.log("PARTIAL LIQUIDATION");
            console2.log("liabilityValue: ", liabilityValue);
            console2.log("results.repay: ", results.repay);
            console2.log("dArgs.dust: ", dArgs.dust);
            console2.log("liabilityValue - results.repay: ", liabilityValue - results.repay);
            console2.log("liabilityValue - results.repay < dArgs.dust", liabilityValue - results.repay < dArgs.dust);
            // results.repay unchanged
            results.dart = results.repay / sArgs.rate;
            console2.log("results.dart: ", results.dart);
            results.dart = sArgs.rate * results.dart < results.repay ? results.dart + 1 : results.dart; // round up
            console2.log("results.dart rounded: ", results.dart);
            results.gemOut = results.repay / collateralSalePrice;
            console2.log("results.gemOut: ", results.gemOut);
            results.collateral = sArgs.collateral - results.gemOut;
            results.normalizedDebt = sArgs.normalizedDebt - results.dart;

            if (results.normalizedDebt != 0) {
                uint256 resultingHealthRatio = getHealthRatio(
                    results.collateral, // [wad]
                    results.normalizedDebt, // [wad]
                    sArgs.rate, // [ray]
                    _sArgs.exchangeRate, // [wad] but converted to ray during calculation
                    dArgs.liquidationThreshold // [ray]
                );
                console2.log("resultingHealthRatio: ", resultingHealthRatio);
            } 

            results.category = 2;
        } else {
            require(false, "panic"); // shouldn't occur
        }

        console2.log("expectedFinalRepay: [rad] ", results.repay);
        console2.log("expectedResultingCollateral: [ray] ", results.collateral);
        console2.log("expectedResultingDebt: [ray]", results.normalizedDebt);

        console2.log("---");
    }

    // solves for the positive x-intercept for the quadratic equation of the form 
    // ax^2 + bx + c = 0 
    // @params a [ray] 
    // @params b [ray] 
    // @params b [ray] 
    function calculateQuadraticEquation(int256 a, int256 b, int256 c, uint256 scale) internal returns (uint256 root) {
        string[] memory inputs = new string[](7); 
        inputs[0] = "bun";
        inputs[1] = "run";
        inputs[2] = "offchain/quadraticSolver.ts";
        inputs[3] = uint256(a).toString(); 
        inputs[4] = uint256(b).toString(); 
        inputs[5] = uint256(c).toString(); 
        inputs[6] = uint256(scale).toString(); // SCALE
        console2.log("inputs[3]: ", inputs[3]);
        console2.log("inputs[4]: ", inputs[4]);
        console2.log("inputs[5]: ", inputs[5]);
        console2.log("inputs[6]: ", inputs[6]);

        string memory output = string(vm.ffi(inputs));
        console2.log("output: ", output); 
        root = vm.parseJsonUint(output, ".root"); 
        console2.log("root: ", root);
    }

    function test_CalculateQuadraticEquation() public {

        // x^2 -2x + 1 = 0 
        int256 a = 1e27; 
        int256 b = -2e27; 
        int256 c = 1e27; 
        assertEq(calculateQuadraticEquation(a, b, c, 27), 1e27); 

        // x^2 - 1 = 0 
        // (0 + sqrt(0-4(1)(-1)) 
        a = 1e27; 
        b = 0e27; 
        c = -1e27; 
        assertEq(calculateQuadraticEquation(a, b, c, 27), 1e27); 
        // x^2 - 2x + 1 = 0
        a = 1e27; 
        b = -2e27; 
        c = 1e27; 
        assertEq(calculateQuadraticEquation(a, b, c, 27), 1e27);
        // x^2 -5x + 6 = 0
        // [ -(-5) + sqrt(25 - 4(1)(6)) ] / (2) = (5 + 1) / 2 = 3 
        // (2, 0), (3, 0), should return 3 the higher root 
        a = 1e27; 
        b = -5e27; 
        c = 6e27; 
        assertEq(calculateQuadraticEquation(a, b, c, 27), 3e27);
        // // 2x^2 - 8 = 0 
        // a = 1e27; 
        // b = 0e27; 
        // c = -8e27; 
        // assertEq(calculateQuadraticEquation(a, b, c, 27), 2);
        // // 10000x^2 + 5000x - 25000 = 0
        // // 1.35
        // a = 10_000e27; 
        // b = 5_000e27; 
        // c = 25000e27; 
        // assertEq(calculateQuadraticEquation(a, b, c, 27), 1);

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
    //     console2.log("resultingCollateral: ", results.collateral);
    //     console2.log("resultingNormalizedDebt: ", results.normalizedDebt);
    //     assertEq(results.collateral, 76166832174776564052, "collateral"); // [ray]
    //     assertEq(results.normalizedDebt, 28943396226415094339, "normalizedDebt"); // [ray]
    // }
}
