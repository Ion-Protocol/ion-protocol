pragma solidity ^0.8.21; 

// import { safeconsole as console } from "forge-std/safeconsole.sol";

import {LiquidationSharedSetup} from "test/helpers/LiquidationSharedSetup.sol";
import { Liquidation } from "src/Liquidation.sol"; 
import { GemJoin } from "../../src/join/GemJoin.sol";
import { RoundedMath } from "src/math/RoundedMath.sol";
import { ReserveOracle } from "src/ReserveOracles/ReserveOracle.sol";
import "forge-std/console.sol"; 

contract MockstEthReserveOracle {

    uint256 public exchangeRate;
    function setExchangeRate(uint256 _exchangeRate) public {
        exchangeRate = _exchangeRate; 
    }
    // @dev called by Liquidation.sol 
    function getExchangeRate(uint256 ilkIndex) public returns (uint256) {
        return exchangeRate; 
    }
}

contract LiquidationTest is LiquidationSharedSetup {
    using RoundedMath for uint256;

    function test_ExchangeRateCannotBeZero() public {
        // deploy liquidations contract 
        uint64[ILK_COUNT] memory liquidationThresholds = getPercentageInWad([75, 75, 75, 75, 75, 75, 75, 75]);
        uint256 _targetHealth = 1.25 ether; 
        uint256 _reserveFactor = 0.02 ether; 
        uint256 _maxDiscount = 0.2 ether; 
        
        liquidation = new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds, _targetHealth, _reserveFactor, _maxDiscount); 

        // set exchange rate to zero
        reserveOracle.setExchangeRate(0); 

        // create borrow position 
        borrow(borrower1, ilkIndex, 10 ether, 5 ether); 

        // liquidate call 
        vm.startPrank(keeper1);
        vm.expectRevert(
            abi.encodeWithSelector(Liquidation.ExchangeRateCannotBeZero.selector, 0) 
        );        
        liquidation.liquidate(ilkIndex, borrower1, keeper1); 
        vm.stopPrank(); 
    }

    /**
     * @dev Test that not unsafe vaults can't be liquidated
     * healthRatio = 10 ether * 1 ether * 0.75 ether / 5 ether / 1 ether 
     *             = 7.5 / 5 = 1.5 
     */
    function test_VaultIsNotUnsafe() public {
        // deploy liquidations contract 
        uint64[ILK_COUNT] memory liquidationThresholds = [0.75 ether, 0, 0, 0, 0, 0, 0, 0];
        uint256 _targetHealth = 1.25 ether; 
        uint256 _reserveFactor = 0.02 ether; 
        uint256 _maxDiscount = 0.2 ether; 
        
        liquidation = new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds, _targetHealth, _reserveFactor, _maxDiscount); 

        // set exchange rate 
        reserveOracle.setExchangeRate(1 ether);

        // create borrow position 
        borrow(borrower1, ilkIndex, 10 ether, 5 ether); 

        // liquidate call 
        vm.startPrank(keeper1);
        vm.expectRevert(
            abi.encodeWithSelector(Liquidation.VaultIsNotUnsafe.selector, 1.5 ether) 
        );
        liquidation.liquidate(ilkIndex, borrower1, keeper1); 
        vm.stopPrank(); 
    }   

    /**
     * @dev Test that vault with health ratio exactly one can't be liquidated
     * healthRatio = 10 ether * 0.5 ether * 1 / 5 ether / 1 ether 
     */
    function test_HealthRatioIsExactlyOne() public {
        // deploy liquidations contract 
        uint64[ILK_COUNT] memory liquidationThresholds = [1 ether, 0, 0, 0, 0, 0, 0, 0];
        uint256 _targetHealth = 1.25 ether; 
        uint256 _reserveFactor = 0.02 ether; 
        uint256 _maxDiscount = 0.2 ether; 
        liquidation = new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds, _targetHealth, _reserveFactor, _maxDiscount); 

        // set exchange rate 
        reserveOracle.setExchangeRate(0.5 ether);

        // create borrow position 
        borrow(borrower1, ilkIndex, 10 ether, 5 ether); 

        // liquidate call 
        vm.startPrank(keeper1);
        vm.expectRevert(
            abi.encodeWithSelector(Liquidation.VaultIsNotUnsafe.selector, 1 ether) 
        );
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
    function test_PartialLiquidationSuccess() public {
        // calculating resulting state after liquidations  
        LiquidationArgs memory args; 
        args.collateral = 100 ether; // [wad] 
        args.liquidationThreshold = 0.5 ether; // [wad]  
        args.exchangeRate = 0.95 ether; // [wad] 
        args.normalizedDebt = 50 ether; // [wad] 
        args.rate = RAY; // [ray] 
        args.targetHealth = 1.25 ether ; // [wad] 
        args.reserveFactor = 0.02 ether; // [wad] 
        args.maxDiscount = 0.2 ether; // [wad] 
        
        Results memory results = calculateExpectedLiquidationResults(args);
        console.log("expectedResultingCollateral: ", results.collateral); 
        console.log("expectedResultingDebt: ", results.normalizedDebt); 
        console.log("liquidation threshold: ", args.liquidationThreshold); 
        console.log("liquidation threshold: ", uint64(args.liquidationThreshold)); 
        console.log("uint64 max: ", type(uint64).max);
        
        uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
       
        liquidation = new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds, args.targetHealth, args.reserveFactor, args.maxDiscount); 
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation)); 

        // create position 
        borrow(borrower1, ilkIndex, 100 ether, 50 ether); 

        // exchangeRate drops 
        reserveOracle.setExchangeRate(args.exchangeRate);

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

        // resulting health ratio is target health ratio 
        uint256 healthRatio = actualResultingCollateral.roundedWadMul(args.exchangeRate).roundedWadMul(args.liquidationThreshold); 
        healthRatio = healthRatio.roundedWadDiv(actualResultingNormalizedDebt).roundedWadDiv(rate.scaleToWad(27)); 
        console.log('new healthRatio: ', healthRatio); 
        assertEq(healthRatio, args.targetHealth, "resulting health ratio"); 
    } 

    // results in number slightly less than 1.25 
    function test_PartialLiquidationSuccessBelowTarget() public {
        // calculating resulting state after liquidations  
        LiquidationArgs memory args; 
        args.collateral = 4.895700865128650483 ether; // [wad] 
        args.liquidationThreshold = 0.8 ether; // [wad]  
        args.exchangeRate = 0.238671394775725980 ether; // [wad] 
        args.normalizedDebt = 1.000000000000000002 ether; // [wad] 
        args.rate = RAY; // [ray] 
        args.targetHealth = 1.25 ether ; // [wad] 
        args.reserveFactor = 0 ether; // [wad] 
        args.maxDiscount = 0.2 ether; // [wad] 
        
        Results memory results = calculateExpectedLiquidationResults(args);
        console.log("expectedResultingCollateral: ", results.collateral); 
        console.log("expectedResultingDebt: ", results.normalizedDebt); 
        console.log("liquidation threshold: ", args.liquidationThreshold); 
        console.log("liquidation threshold: ", uint64(args.liquidationThreshold)); 
        console.log("uint64 max: ", type(uint64).max);
        
        uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
       
        liquidation = new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds, args.targetHealth, args.reserveFactor, args.maxDiscount); 
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation)); 

        // create position 
        borrow(borrower1, ilkIndex, args.collateral, args.normalizedDebt); 

        // exchangeRate drops 
        reserveOracle.setExchangeRate(args.exchangeRate);

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
        uint256 healthRatio = actualResultingCollateral.roundedWadMul(args.exchangeRate).roundedWadMul(args.liquidationThreshold); 
        healthRatio = healthRatio.roundedWadDiv(actualResultingNormalizedDebt).roundedWadDiv(rate.scaleToWad(27)); 
        console.log('new healthRatio: ', healthRatio); 
        assertEq(healthRatio, args.targetHealth, "resulting health ratio"); 

    }

    function test_PartialLiquidationSuccessWithRate() public {
        // calculating resulting state after liquidations  
        LiquidationArgs memory args; 
        args.collateral = 100 ether; // [wad] 
        args.liquidationThreshold = 0.5 ether; // [wad]  
        args.exchangeRate = 0.95 ether; // [wad] 
        args.normalizedDebt = 50 ether; // [wad] 
        args.rate = 1.12323423423 ether * RAY / WAD; // [ray] 
        args.targetHealth = 1.25 ether ; // [wad] 
        args.reserveFactor = 0.02 ether; // [wad] 
        args.maxDiscount = 0.2 ether; // [wad] 
        
        Results memory results = calculateExpectedLiquidationResults(args);

        console.log("expectedResultingCollateral: ", results.collateral); 
        console.log("expectedResultingDebt: ", results.normalizedDebt); 
        console.log("liquidation threshold: ", args.liquidationThreshold); 
        console.log("liquidation threshold: ", uint64(args.liquidationThreshold)); 
        console.log("uint64 max: ", type(uint64).max);
        uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
        liquidation = new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds, args.targetHealth, args.reserveFactor, args.maxDiscount); 
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation)); 

        // create position 
        borrow(borrower1, ilkIndex, 100 ether, 50 ether); 

        // exchangeRate drops 
        reserveOracle.setExchangeRate(args.exchangeRate);

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
        // assertEq(actualResultingCollateral, expectedResultingCollateral, "resulting collateral"); 
        // assertEq(actualResultingNormalizedDebt, expectedResultingNormalizedDebt, "resulting normalizedDebt"); 

        // resulting health ratio is target health ratio 
        uint256 healthRatio = actualResultingCollateral.roundedWadMul(args.exchangeRate).roundedWadMul(args.liquidationThreshold); 
        healthRatio = healthRatio.roundedWadDiv(actualResultingNormalizedDebt).roundedWadDiv(rate.scaleToWad(27)); 
        console.log('new healthRatio: ', healthRatio); 
        assertEq(healthRatio, args.targetHealth, "resulting health ratio"); 
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
        LiquidationArgs memory args; 
        args.collateral = 100 ether; // [wad] 
        args.liquidationThreshold = 0.5 ether; // [wad]  
        args.exchangeRate = 0.95 ether; // [wad] 
        args.normalizedDebt = 50 ether; // [wad] 
        args.rate = 1.12323423423 ether * RAY / WAD; // [ray] 
        args.targetHealth = 1.25 ether ; // [wad] 
        args.reserveFactor = 0.02 ether; // [wad] 
        args.maxDiscount = 0.2 ether; // [wad] 

        uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
        liquidation = new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds, args.targetHealth, args.reserveFactor, args.maxDiscount); 
    
    }

    /**
     * @dev Partial liquidation leaves dust so goes into full liquidations for liquidator 
     * Resulting normalizedDebt should be zero 
     * Resulting collateral should be zero or above zero
     */
    function test_LiquidatorPaysForDust() public {

    }



}
