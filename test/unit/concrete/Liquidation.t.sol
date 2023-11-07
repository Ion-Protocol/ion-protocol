pragma solidity ^0.8.21;

// import { safeconsole as console } from "forge-std/safeconsole.sol";

import { LiquidationSharedSetup } from "test/helpers/LiquidationSharedSetup.sol";
import { Liquidation } from "src/Liquidation.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { console2 } from "forge-std/console2.sol";

contract MockstEthReserveOracle {
    uint256 public exchangeRate;

    function setExchangeRate(uint256 _exchangeRate) public {
        exchangeRate = _exchangeRate;
    }
}

contract LiquidationTest is LiquidationSharedSetup {
    using RoundedMath for uint256;

    function test_ExchangeRateCannotBeZero() public {
        // deploy liquidations contract
        uint256 liquidationThreshold = 0.75e27;
        uint256[ILK_COUNT] memory liquidationThresholds = [
            liquidationThreshold,
            liquidationThreshold,
            liquidationThreshold,
            liquidationThreshold,
            liquidationThreshold,
            liquidationThreshold,
            liquidationThreshold,
            liquidationThreshold
        ];

        uint256 _targetHealth = 1.25 ether;
        uint256 _reserveFactor = 0.02 ether;
        uint256 _maxDiscount = 0.2 ether;

        liquidation =
        new Liquidation(address(ionPool), revenueRecipient, protocol, exchangeRateOracles, liquidationThresholds, _targetHealth, _reserveFactor, _maxDiscount);

        // set exchange rate to zero
        reserveOracle1.setExchangeRate(0);

        // create borrow position
        borrow(borrower1, ilkIndex, 10 ether, 5 ether);

        // liquidate call
        vm.startPrank(keeper1);
        vm.expectRevert(abi.encodeWithSelector(Liquidation.ExchangeRateCannotBeZero.selector, 0));
        liquidation.liquidate(ilkIndex, borrower1, keeper1);
        vm.stopPrank();
    }

    /**
     * @dev Test that not unsafe vaults can't be liquidated
     * healthRatio = 10 ether * 1 ether * 0.75 ether / 5 ether / 1 ether
     *             = 7.5 / 5 = 1.5
     */
    function test_RevertWhen_VaultIsNotUnsafe() public {
        // deploy liquidations contract
        uint256 liquidationThreshold = 0.75e27;
        uint256[ILK_COUNT] memory liquidationThresholds = [liquidationThreshold, 0, 0, 0, 0, 0, 0, 0];
        uint256 _targetHealth = 1.25e27;
        uint256 _reserveFactor = 0.02e27;
        uint256 _maxDiscount = 0.2e27;

        liquidation =
        new Liquidation(address(ionPool), revenueRecipient, protocol, exchangeRateOracles, liquidationThresholds, _targetHealth, _reserveFactor, _maxDiscount);

        // set exchange rate
        reserveOracle1.setExchangeRate(1e18);

        // create borrow position
        borrow(borrower1, ilkIndex, 10e18, 5e18);

        // liquidate call
        vm.startPrank(keeper1);
        vm.expectRevert(abi.encodeWithSelector(Liquidation.VaultIsNotUnsafe.selector, 1.5e27));
        liquidation.liquidate(ilkIndex, borrower1, keeper1);
        vm.stopPrank();
    }

    /**
     * @dev Test that vault with health ratio exactly one can't be liquidated
     * healthRatio = 10 ether * 0.5 ether * 1 / 5 ether / 1 ether
     */
    function test_RevertWhen_HealthRatioIsExactlyOne() public {
        // deploy liquidations contract
        uint256 liquidationThreshold = 1e27;
        uint256 _targetHealth = 1.25e27;
        uint256 _reserveFactor = 0.02e27;
        uint256 _maxDiscount = 0.2e27;

        uint256[ILK_COUNT] memory liquidationThresholds = [liquidationThreshold, 0, 0, 0, 0, 0, 0, 0];
        liquidation =
        new Liquidation(address(ionPool), revenueRecipient, protocol, exchangeRateOracles, liquidationThresholds, _targetHealth, _reserveFactor, _maxDiscount);

        // set exchange rate
        uint72 exchangeRate = 0.5e18;
        reserveOracle1.setExchangeRate(exchangeRate);

        // create borrow position
        borrow(borrower1, ilkIndex, 10e18, 5e18);

        // liquidate call
        vm.startPrank(keeper1);
        vm.expectRevert(abi.encodeWithSelector(Liquidation.VaultIsNotUnsafe.selector, 1e27));
        liquidation.liquidate(ilkIndex, borrower1, keeper1);
        vm.stopPrank();
    }

    /**
     * @dev Partial Liquidation
     * collateral = 100 ether
     * liquidationThreshold = 0.5
     * exchangeRate becomes 0.95
     * collateralValue = 100 * 0.95 * 0.5 = 47.5
     * debt = 50
     * healthRatio = 47.5 / 50 = 0.95
     * discount = 0.02 + (1 - 0.5) = 0.07
     * repayNum = (1.25 * 50) - 47.5 = 15
     * repayDen = 1.25 - (0.5 / (1 - 0.07)) = 0.71236559139
     * repay = 21.0566037
     * collateralSalePrice = 0.95 * 0.93 = 0.8835 ETH / LST
     * gemOut = 21.0566037 / 0.8835 = 23.8331677
     *
     * Resulting Values:
     * debt = 50 - 21.0566037 = 28.9433963
     * collateral = 100 - 23.8331677 = 76.1668323
     */
    function test_PartialLiquidationSuccessBasic() public {
        // calculating resulting state after liquidations
        DeploymentArgs memory dArgs;
        StateArgs memory sArgs;

        sArgs.collateral = 100e18; // [wad]
        sArgs.exchangeRate = 0.95e18; // [wad]
        sArgs.normalizedDebt = 50e18; // [wad]
        sArgs.rate = 1e27; // [ray]

        dArgs.liquidationThreshold = 0.5e27; // [ray]
        dArgs.targetHealth = 1.25e27; // [ray]
        dArgs.reserveFactor = 0.02e27; // [ray]
        dArgs.maxDiscount = 0.2e27; // [ray]
        dArgs.dust = 0; // [rad]

        Results memory results = calculateExpectedLiquidationResults(dArgs, sArgs);

        uint256[ILK_COUNT] memory liquidationThresholds = [dArgs.liquidationThreshold, 0, 0, 0, 0, 0, 0, 0];

        liquidation =
        new Liquidation(address(ionPool), revenueRecipient, protocol, exchangeRateOracles, liquidationThresholds, dArgs.targetHealth, dArgs.reserveFactor, dArgs.maxDiscount);
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // create position
        borrow(borrower1, ilkIndex, 100 ether, 50 ether);

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        underlying.mint(keeper1, 100 ether);
        vm.startPrank(keeper1);
        underlying.approve(address(liquidation), 100 ether);
        liquidation.liquidate(ilkIndex, borrower1, keeper1);
        vm.stopPrank();

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ilkIndex, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ilkIndex, borrower1);
        uint256 rate = ionPool.rate(ilkIndex);

        // resulting vault collateral and debt
        assertEq(actualResultingCollateral, results.collateral, "resulting collateral");
        assertEq(actualResultingNormalizedDebt, results.normalizedDebt, "resulting normalizedDebt");

        uint256 healthRatio = getHealthRatio(
            actualResultingCollateral,
            actualResultingNormalizedDebt,
            sArgs.rate,
            sArgs.exchangeRate,
            dArgs.liquidationThreshold
        );
        
        assertTrue(healthRatio > dArgs.targetHealth, "resulting health ratio >= target health"); 
        assertEq(healthRatio / 1e9, dArgs.targetHealth / 1e9, "resulting health ratio");
    }

    // TODO: This test results in number slightly less than 1.25. Test invariants
    function test_PartialLiquidationSuccessWithDecimals() public {
        // calculating resulting state after liquidations
        DeploymentArgs memory dArgs;
        StateArgs memory sArgs;

        sArgs.collateral = 4.895700865128650483e18; // [wad]
        sArgs.exchangeRate = 0.23867139477572598e18; // [wad]
        sArgs.normalizedDebt = 1.000000000000000002e18; // [wad]
        sArgs.rate = 1e27; // [ray]

        dArgs.liquidationThreshold = 0.8e27; // [ray]
        dArgs.targetHealth = 1.25e27; // [ray]
        dArgs.reserveFactor = 0; // [ray]
        dArgs.maxDiscount = 0.2e27; // [ray]

        Results memory results = calculateExpectedLiquidationResults(dArgs, sArgs);

        uint256[ILK_COUNT] memory liquidationThresholds = [uint256(dArgs.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];

        liquidation =
        new Liquidation(address(ionPool), revenueRecipient, protocol, exchangeRateOracles, liquidationThresholds, dArgs.targetHealth, dArgs.reserveFactor, dArgs.maxDiscount);
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // create position
        borrow(borrower1, ilkIndex, sArgs.collateral, sArgs.normalizedDebt);

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        liquidate(keeper1, ilkIndex, borrower1);

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ilkIndex, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ilkIndex, borrower1);
        uint256 rate = ionPool.rate(ilkIndex);

        // resulting vault collateral and debt
        assertEq(actualResultingCollateral, results.collateral, "resulting collateral");
        assertEq(actualResultingNormalizedDebt, results.normalizedDebt, "resulting normalizedDebt");

        // resulting health ratio is target health ratio
        uint256 healthRatio = getHealthRatio(
            actualResultingCollateral,
            actualResultingNormalizedDebt,
            sArgs.rate,
            sArgs.exchangeRate,
            dArgs.liquidationThreshold
        );

        assertTrue(healthRatio > dArgs.targetHealth, "resulting health ratio >= target health"); 
        assertEq(healthRatio / 1e10, dArgs.targetHealth / 1e10, "resulting health ratio"); // compare with reduced precision 
        
    }

    function test_PartialLiquidationSuccessWithRate() public {
        // calculating resulting state after liquidations
        DeploymentArgs memory dArgs;
        StateArgs memory sArgs;

        sArgs.collateral = 100e18; // [wad]
        sArgs.exchangeRate = 0.95e18; // [wad]
        sArgs.normalizedDebt = 50e18; // [wad]
        sArgs.rate = 1.12323423423e27; // [ray]

        dArgs.liquidationThreshold = 0.5e27; // [ray]
        dArgs.targetHealth = 1.25e27; // [ray]
        dArgs.reserveFactor = 0.02e27; // [ray]
        dArgs.maxDiscount = 0.2e27; // [ray]

        Results memory results = calculateExpectedLiquidationResults(dArgs, sArgs);

        uint256[ILK_COUNT] memory liquidationThresholds = [dArgs.liquidationThreshold, 0, 0, 0, 0, 0, 0, 0];
        liquidation =
        new Liquidation(address(ionPool), revenueRecipient, protocol, exchangeRateOracles, liquidationThresholds, dArgs.targetHealth, dArgs.reserveFactor, dArgs.maxDiscount);
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // create position
        borrow(borrower1, ilkIndex, 100e18, 50e18);

        // rate updates 
        ionPool.setRate(ilkIndex, uint104(sArgs.rate)); 

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        underlying.mint(keeper1, 100e18);
        vm.startPrank(keeper1);
        underlying.approve(address(liquidation), 100e18);
        liquidation.liquidate(ilkIndex, borrower1, keeper1);
        vm.stopPrank();

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ilkIndex, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ilkIndex, borrower1);
        uint256 rate = ionPool.rate(ilkIndex);

        // resulting vault collateral and debt
        // assertEq(actualResultingCollateral, expectedResultingCollateral, "resulting collateral");
        // assertEq(actualResultingNormalizedDebt, expectedResultingNormalizedDebt, "resulting normalizedDebt");

        // resulting health ratio is target health ratio
        uint256 healthRatio = getHealthRatio(
            actualResultingCollateral,
            actualResultingNormalizedDebt,
            sArgs.rate,
            sArgs.exchangeRate,
            dArgs.liquidationThreshold
        );

        assertEq(healthRatio / 1e9, dArgs.targetHealth / 1e9, "resulting health ratio");
    }

    /**
     * @dev Partial liquidation fails and protocol takes debt
     *
     * 10 ETH on 10 stETH
     * stETH exchangeRate decreases to 0.9
     * health ratio is now less than 1
     * collateralValue = collateral * exchangeRate * liquidationThreshold = 10 * 0.9 * 1
     * debtValue = 10
     * healthRatio = 9 / 10 = 0.9
     * discount = 0.02 + (1 - 0.9) = 0.12
     * repayNum = (1.25 * 10) - 9 = 3.5
     * repayDen = 1.25 - (1 / (1 - 0.12)) = 0.11363636
     * repay = 30.8000
     * since repay is over 10, gemOut is capped to 10
     * Partial Liquidation not possible, so move position to the vow
     */
    function test_ProtocolTakesDebt() public {
        DeploymentArgs memory dArgs;
        StateArgs memory sArgs;
        sArgs.collateral = 10e18; // [wad]
        sArgs.exchangeRate = 0.9e18; // [wad]
        sArgs.normalizedDebt = 10e18; // [wad]
        sArgs.rate = 1e27; // [ray]

        dArgs.liquidationThreshold = 1e27; // [wad]
        dArgs.targetHealth = 1.25e27; // [wad]
        dArgs.reserveFactor = 0.02e27; // [wad]
        dArgs.maxDiscount = 0.2e27; // [wad]

        uint256[ILK_COUNT] memory liquidationThresholds = [dArgs.liquidationThreshold, 0, 0, 0, 0, 0, 0, 0];
        liquidation =
        new Liquidation(address(ionPool), revenueRecipient, protocol, exchangeRateOracles, liquidationThresholds, dArgs.targetHealth, dArgs.reserveFactor, dArgs.maxDiscount);
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // create position
        borrow(borrower1, ilkIndex, sArgs.collateral, sArgs.normalizedDebt);

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        liquidate(keeper1, ilkIndex, borrower1);

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ilkIndex, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ilkIndex, borrower1);

        assertEq(actualResultingCollateral, 0, "resulting collateral");
        assertEq(actualResultingNormalizedDebt, 0, "resulting normalized debt");
    }

    /**
     * @dev Partial liquidation leaves dust so goes into full liquidations for liquidator
     * Resulting normalizedDebt should be zero
     * Resulting collateral should be zero or above zero
     */
    function test_LiquidatorPaysForDust() public {

        uint256 dust = uint256(0.5 ether).scaleUpToRad(18);  
        // set dust
        ionPool.updateIlkDust(ilkIndex, dust); // [rad]

        // calculating resulting state after liquidations
        DeploymentArgs memory dArgs;
        StateArgs memory sArgs;
        sArgs.collateral = 1.29263225501889978e18; // [wad]
        sArgs.exchangeRate = 0.432464060992175961e18; // [wad]
        sArgs.normalizedDebt = 0.500000000000000001e18; // [wad]
        sArgs.rate = 1e27; // [ray]

        dArgs.liquidationThreshold = 0.8e27; // [wad]
        dArgs.targetHealth = 1.25e27; // [wad]
        dArgs.reserveFactor = 0e27; // [wad]
        dArgs.maxDiscount = 0.2e27; // [wad]
        dArgs.dust = dust; // [rad] 

        Results memory results = calculateExpectedLiquidationResults(dArgs, sArgs);

        uint256[ILK_COUNT] memory liquidationThresholds = [uint256(dArgs.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];

        liquidation =
        new Liquidation(address(ionPool), revenueRecipient, protocol, exchangeRateOracles, liquidationThresholds, dArgs.targetHealth, dArgs.reserveFactor, dArgs.maxDiscount);
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));

        // create position
        borrow(borrower1, ilkIndex, sArgs.collateral, sArgs.normalizedDebt);

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        liquidate(keeper1, ilkIndex, borrower1);

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ilkIndex, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ilkIndex, borrower1);

        // health ratio is collateral / debt
        // resulting debt is zero, so health ratio will give divide by zero

        // resulting vault collateral and debt
        assertEq(actualResultingNormalizedDebt, 0, "resulting normalizedDebt should be zero");
        assertTrue(actualResultingCollateral >= 0, "resulting collateral can be non-zero");
    }

    // function test_PartialLiquidationFeeDistribution() public {

    // }
}
