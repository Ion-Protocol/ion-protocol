pragma solidity ^0.8.21;

// import { safeconsole as console } from "forge-std/safeconsole.sol";

import { LiquidationSharedSetup } from "test/helpers/LiquidationSharedSetup.sol";
import { Liquidation } from "src/Liquidation.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";
import "forge-std/console.sol";

contract MockstEthReserveOracle {
    uint256 public exchangeRate;

    function setExchangeRate(uint256 _exchangeRate) public {
        exchangeRate = _exchangeRate;
    }
}

contract LiquidationTest is LiquidationSharedSetup {
    using WadRayMath for uint256;

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
        borrow(borrower1, ILK_INDEX, 10 ether, 5 ether);

        // liquidate call
        vm.startPrank(keeper1);
        vm.expectRevert(abi.encodeWithSelector(Liquidation.ExchangeRateCannotBeZero.selector, 0));
        liquidation.liquidate(ILK_INDEX, borrower1, keeper1);
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
        borrow(borrower1, ILK_INDEX, 10e18, 5e18);

        // liquidate call
        vm.startPrank(keeper1);
        vm.expectRevert(abi.encodeWithSelector(Liquidation.VaultIsNotUnsafe.selector, 1.5e27));
        liquidation.liquidate(ILK_INDEX, borrower1, keeper1);
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
        borrow(borrower1, ILK_INDEX, 10e18, 5e18);

        // liquidate call
        vm.startPrank(keeper1);
        vm.expectRevert(abi.encodeWithSelector(Liquidation.VaultIsNotUnsafe.selector, 1e27));
        liquidation.liquidate(ILK_INDEX, borrower1, keeper1);
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
        uint256 keeperInitialUnderlying = 100 ether; 

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
        borrow(borrower1, ILK_INDEX, 100 ether, 50 ether);

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        underlying.mint(keeper1, keeperInitialUnderlying);
        vm.startPrank(keeper1);
        underlying.approve(address(liquidation), keeperInitialUnderlying);
        liquidation.liquidate(ILK_INDEX, borrower1, keeper1);
        vm.stopPrank();

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ILK_INDEX, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ILK_INDEX, borrower1);

        uint256 healthRatio = getHealthRatio(
            actualResultingCollateral,
            actualResultingNormalizedDebt,
            sArgs.rate,
            sArgs.exchangeRate,
            dArgs.liquidationThreshold
        );

        uint256 expectedWethPaid = results.repay / RAY; 
        expectedWethPaid = expectedWethPaid * RAY < results.repay ? expectedWethPaid + 1 : expectedWethPaid; 

        uint256 expectedGemFee = results.gemOut.rayMulUp(dArgs.reserveFactor);

        // resulting vault collateral and debt
        assertEq(actualResultingCollateral, results.collateral, "resulting collateral");
        assertEq(actualResultingNormalizedDebt, results.normalizedDebt, "resulting normalizedDebt");

        // target health ratio reached         
        assertTrue(healthRatio > dArgs.targetHealth, "resulting health ratio >= target health"); 
        assertEq(healthRatio / 1e9, dArgs.targetHealth / 1e9, "resulting health ratio");

        // no remaining bad debt, collateral, or ERC20 in liquidations contract
        assertEq(ionPool.unbackedDebt(address(liquidation)), 0, "no unbacked debt left in liquidation contract"); 
        assertEq(ionPool.gem(ILK_INDEX, address(liquidation)), 0, "no gem left in liquidation contract"); 
        assertEq(ionPool.underlying().balanceOf(address(liquidation)), 0, "no weth left in liquidation contract"); 

        // nothing went to protocol contract 
        assertEq(ionPool.unbackedDebt(protocol), 0, "no unbacked debt in protocol"); 
        assertEq(ionPool.gem(ILK_INDEX, address(liquidation)), 0, "no gem in protocol"); 
        assertEq(ionPool.underlying().balanceOf(address(liquidation)), 0, "no weth left in protocol"); 

        // keeper gets the collaterals sold
        console.log("results.gemOut: ", results.gemOut);
        assertEq(ionPool.gem(ILK_INDEX, keeper1), results.gemOut - expectedGemFee, "keeper gem");
        assertEq(ionPool.underlying().balanceOf(keeper1), keeperInitialUnderlying - expectedWethPaid, "keeper weth");
    
        // revenue recipient gets the fees 
        assertEq(ionPool.gem(ILK_INDEX, revenueRecipient), expectedGemFee, "revenue recipient gem");
    }

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
        borrow(borrower1, ILK_INDEX, sArgs.collateral, sArgs.normalizedDebt);

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        uint256 keeperInitialUnderlying = liquidate(keeper1, ILK_INDEX, borrower1);

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ILK_INDEX, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ILK_INDEX, borrower1);

        uint256 healthRatio = getHealthRatio(
            actualResultingCollateral,
            actualResultingNormalizedDebt,
            sArgs.rate,
            sArgs.exchangeRate,
            dArgs.liquidationThreshold
        );

        uint256 expectedWethPaid = results.repay / RAY; 
        expectedWethPaid = expectedWethPaid * RAY < results.repay ? expectedWethPaid + 1 : expectedWethPaid; 

        uint256 expectedGemFee = results.gemOut.rayMulUp(dArgs.reserveFactor); 

        // resulting vault collateral and debt
        assertEq(actualResultingCollateral, results.collateral, "resulting collateral");
        assertEq(actualResultingNormalizedDebt, results.normalizedDebt, "resulting normalizedDebt");

        // reached target health ratio 
        assertTrue(healthRatio > dArgs.targetHealth, "resulting health ratio >= target health"); 
        assertEq(healthRatio / 1e10, dArgs.targetHealth / 1e10, "resulting health ratio"); // compare with reduced precision 
        
        // no remaining bad debt, collateral, or ERC20 in liquidations contract
        assertEq(ionPool.unbackedDebt(address(liquidation)), 0, "no unbacked debt left in liquidation contract"); 
        assertEq(ionPool.gem(ILK_INDEX, address(liquidation)), 0, "no gem left in liquidation contract"); 
        assertEq(ionPool.underlying().balanceOf(address(liquidation)), 0, "no weth left in liquidation contract"); 

        // nothing went to protocol contract 
        assertEq(ionPool.unbackedDebt(protocol), 0, "no unbacked debt in protocol"); 
        assertEq(ionPool.gem(ILK_INDEX, address(liquidation)), 0, "no gem in protocol"); 
        assertEq(ionPool.underlying().balanceOf(address(liquidation)), 0, "no weth left in protocol"); 

        // keeper gets the collaterals sold
        assertEq(ionPool.gem(ILK_INDEX, keeper1), results.gemOut - expectedGemFee, "keeper gem");
        assertEq(ionPool.underlying().balanceOf(keeper1), keeperInitialUnderlying - expectedWethPaid, "keeper weth");
    
        // revenue recipient gets the fees 
        assertEq(ionPool.gem(ILK_INDEX, revenueRecipient), expectedGemFee, "revenue recipient gem"); 
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
        borrow(borrower1, ILK_INDEX, 100e18, 50e18);

        // rate updates 
        ionPool.setRate(ILK_INDEX, uint104(sArgs.rate)); 
        assertEq(ionPool.rate(ILK_INDEX), uint104(sArgs.rate)); 

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        uint256 keeperInitialUnderlying = liquidate(keeper1, ILK_INDEX, borrower1);

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ILK_INDEX, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ILK_INDEX, borrower1);

        uint256 expectedWethPaid = results.repay / RAY; 
        expectedWethPaid = expectedWethPaid * RAY < results.repay ? expectedWethPaid + 1 : expectedWethPaid; 

        uint256 expectedGemFee = results.gemOut.rayMulUp(dArgs.reserveFactor); 

        uint256 healthRatio = getHealthRatio(
            actualResultingCollateral,
            actualResultingNormalizedDebt,
            sArgs.rate,
            sArgs.exchangeRate,
            dArgs.liquidationThreshold
        );

        // resulting vault collateral and debt
        assertEq(actualResultingCollateral, results.collateral, "resulting collateral");
        assertEq(actualResultingNormalizedDebt, results.normalizedDebt, "resulting normalizedDebt");

        // reached target health ratio 
        assertEq(healthRatio / 1e9, dArgs.targetHealth / 1e9, "resulting health ratio");

        // no remaining bad debt, collateral, or ERC20 in liquidations contract
        assertEq(ionPool.unbackedDebt(address(liquidation)), 0, "no unbacked debt left in liquidation contract"); 
        assertEq(ionPool.gem(ILK_INDEX, address(liquidation)), 0, "no gem left in liquidation contract"); 
        assertEq(ionPool.underlying().balanceOf(address(liquidation)), 0, "no weth left in liquidation contract"); 

        // nothing went to protocol contract 
        assertEq(ionPool.unbackedDebt(protocol), 0, "no unbacked debt in protocol"); 
        assertEq(ionPool.gem(ILK_INDEX, address(liquidation)), 0, "no gem in protocol"); 
        assertEq(ionPool.underlying().balanceOf(address(liquidation)), 0, "no weth left in protocol"); 

        // keeper gets the collaterals sold
        assertEq(ionPool.gem(ILK_INDEX, keeper1), results.gemOut - expectedGemFee, "keeper gem");
        assertEq(ionPool.underlying().balanceOf(keeper1), keeperInitialUnderlying - expectedWethPaid, "keeper weth");
    
        // revenue recipient gets the fees 
        assertEq(ionPool.gem(ILK_INDEX, revenueRecipient), expectedGemFee, "revenue recipient gem"); 
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
        borrow(borrower1, ILK_INDEX, sArgs.collateral, sArgs.normalizedDebt);

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        uint256 keeperInitialUnderlying = liquidate(keeper1, ILK_INDEX, borrower1);

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ILK_INDEX, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ILK_INDEX, borrower1);

        // entire position is moved 
        assertEq(actualResultingCollateral, 0, "resulting collateral");
        assertEq(actualResultingNormalizedDebt, 0, "resulting normalized debt");

        // protocol takes on position 
        assertEq(ionPool.unbackedDebt(protocol), sArgs.normalizedDebt * sArgs.rate, "protocol unbacked debt"); 
        assertEq(ionPool.gem(ILK_INDEX, protocol), sArgs.collateral, "protocol gem"); 

        // keeper is untouched
        assertEq(ionPool.underlying().balanceOf(keeper1), keeperInitialUnderlying, "keeper underlying balance"); 
        assertEq(ionPool.gem(ILK_INDEX, keeper1), 0, "keeper gem"); 
    }

    /**
     * @dev Partial liquidation leaves dust so goes into full liquidations for liquidator
     * Resulting normalizedDebt should be zero
     * Resulting collateral should be zero or above zero
     */
    function test_LiquidatorPaysForDust() public {

        uint256 dust = uint256(0.5 ether).scaleUpToRad(18);  
        // set dust
        ionPool.updateIlkDust(ILK_INDEX, dust); // [rad]

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
        borrow(borrower1, ILK_INDEX, sArgs.collateral, sArgs.normalizedDebt);

        // exchangeRate drops
        reserveOracle1.setExchangeRate(uint72(sArgs.exchangeRate));

        // liquidate
        uint256 keeperInitialUnderlying = liquidate(keeper1, ILK_INDEX, borrower1);

        // results
        uint256 actualResultingCollateral = ionPool.collateral(ILK_INDEX, borrower1);
        uint256 actualResultingNormalizedDebt = ionPool.normalizedDebt(ILK_INDEX, borrower1);

        console.log("test: results.repay: ", results.repay);
        uint256 expectedWethPaid = results.repay / RAY; 
        expectedWethPaid = expectedWethPaid * RAY < results.repay ? expectedWethPaid + 1 : expectedWethPaid; 
        console.log("test: expectedWethPaid: ", expectedWethPaid);

        uint256 expectedGemFee = results.gemOut.rayMulUp(dArgs.reserveFactor);  

        // health ratio is collateral / debt
        // resulting debt is zero, so health ratio will give divide by zero

        // resulting vault collateral and debt
        assertEq(actualResultingNormalizedDebt, results.normalizedDebt, "resulting normalizedDebt should be zero");
        assertTrue(actualResultingCollateral >= results.collateral, "resulting collateral can be non-zero");
    
        // no remaining bad debt, collateral, or ERC20 in liquidations contract
        assertEq(ionPool.unbackedDebt(address(liquidation)), 0, "no unbacked debt left in liquidation contract"); 
        assertEq(ionPool.gem(ILK_INDEX, address(liquidation)), 0, "no gem left in liquidation contract"); 
        assertEq(ionPool.underlying().balanceOf(address(liquidation)), 0, "no weth left in liquidation contract"); 

        // nothing went to protocol contract 
        assertEq(ionPool.unbackedDebt(protocol), 0, "no unbacked debt in protocol"); 
        assertEq(ionPool.gem(ILK_INDEX, address(liquidation)), 0, "no gem in protocol"); 
        assertEq(ionPool.underlying().balanceOf(address(liquidation)), 0, "no weth left in protocol"); 

        // keeper gets the collaterals sold
        console.log("keeper collateral"); 
        assertEq(ionPool.gem(ILK_INDEX, keeper1), results.gemOut - expectedGemFee, "keeper gem");
        console.log("keeper underlying"); 
        console.log("keeperInitialUnderlying: ", keeperInitialUnderlying);
        assertEq(ionPool.underlying().balanceOf(keeper1), keeperInitialUnderlying - expectedWethPaid, "keeper weth");
    
        // revenue recipient gets the fees 
        assertEq(ionPool.gem(ILK_INDEX, revenueRecipient), expectedGemFee, "revenue recipient gem"); 
    }
}
