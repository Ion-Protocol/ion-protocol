// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { IonPoolSharedSetup, MockReserveOracle } from "../helpers/IonPoolSharedSetup.sol";
import { Liquidation } from "src/Liquidation.sol";
import { GemJoin } from "src/join/GemJoin.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract LiquidationSharedSetup is IonPoolSharedSetup {
    using WadRayMath for uint256;
    using Math for uint256;
    using Strings for uint256;
    using SafeCast for *;

    uint256 constant WAD = 1e18;
    uint256 constant RAY = 1e27;

    uint32 constant ILK_COUNT = 8;
    uint8 constant ILK_INDEX = 0;

    uint256 constant DEBT_CEILING = uint256(int256(-1));

    Liquidation public liquidation;
    GemJoin public gemJoin;

    MockReserveOracle public reserveOracle1;
    MockReserveOracle public reserveOracle2;
    MockReserveOracle public reserveOracle3;

    address[] public exchangeRateOracles;

    address immutable keeper1 = vm.addr(99);
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

        ionPool.updateIlkDebtCeiling(ILK_INDEX, DEBT_CEILING);

        supply(lender1, 100 ether);

        reserveOracle1 = new MockReserveOracle(0);
        reserveOracle2 = new MockReserveOracle(0);
        reserveOracle3 = new MockReserveOracle(0);

        exchangeRateOracles = [address(reserveOracle1), address(reserveOracle2), address(reserveOracle3)];
    }

    /**
     * @dev override for test set up
     */
    function _getDebtCeiling(uint8 ilkIndex) internal view override returns (uint256) {
        if (ilkIndex == ILK_INDEX) {
            return DEBT_CEILING;
        } else {
            return debtCeilings[ilkIndex];
        }
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

    function liquidate(address keeper, uint8 ilkIndex, address vault) internal returns (uint256 totalDebt) {
        totalDebt = ionPool.normalizedDebt(ilkIndex, vault).rayMulUp(ionPool.rate(ilkIndex)); // [wad]
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
        pure
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

        uint256 liabilityValue = (sArgs.rate * sArgs.normalizedDebt); // [rad]

        uint256 healthRatio = collateralValue.rayDivDown(liabilityValue); // [ray]

        uint256 discount = dArgs.reserveFactor + (RAY - healthRatio); // [ray]
        discount = discount <= dArgs.maxDiscount ? discount : dArgs.maxDiscount; // [ray]

        uint256 repayNum = liabilityValue.rayMulUp(dArgs.targetHealth) - collateralValue; // [rad] - [rad]

        uint256 repayDen = dArgs.targetHealth - dArgs.liquidationThreshold.rayDivUp(RAY - discount);

        results.repay = repayNum.rayDivUp(repayDen);

        uint256 collateralSalePrice = sArgs.exchangeRate.rayMulUp(RAY - discount);

        if (results.repay > liabilityValue) {
            // if repay > liabilityValue, then liabilityValue / collateralSalePrice > collateral
            assert(liabilityValue / collateralSalePrice >= sArgs.collateral);
            results.dart = sArgs.normalizedDebt;
            results.gemOut = sArgs.collateral;

            results.collateral = 0;
            results.normalizedDebt = 0;

            results.category = 0;
        } else if (liabilityValue - results.repay < dArgs.dust) {
            results.repay = liabilityValue;

            results.dart = sArgs.normalizedDebt;
            results.gemOut = liabilityValue / collateralSalePrice;

            results.collateral = sArgs.collateral - results.gemOut;
            results.normalizedDebt = 0;

            results.category = 1;
        } else if (liabilityValue - results.repay >= dArgs.dust) {
            // results.repay unchanged
            results.dart = results.repay / sArgs.rate;
            results.dart = sArgs.rate * results.dart < results.repay ? results.dart + 1 : results.dart; // round up
            results.gemOut = results.repay / collateralSalePrice;
            results.collateral = sArgs.collateral - results.gemOut;
            results.normalizedDebt = sArgs.normalizedDebt - results.dart;
            results.repay = results.dart * sArgs.rate;
            results.category = 2;
        } else {
            require(false, "panic"); // shouldn't occur
        }
    }
}
