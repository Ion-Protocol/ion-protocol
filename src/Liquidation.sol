// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { RoundedMath, WAD, RAY } from "../src/math/RoundedMath.sol"; 
import {IonPool} from "src/IonPool.sol"; 
import "forge-std/console.sol";

// TODO: import instead when ReserveOracle is finished
interface IReserveOracle {
    function getExchangeRate(uint ilkIndex) external view returns (uint256 exchangeRate); 
}

// DEPLOY PARAMETERS
// NOTE: Needs to be configured on each deployment along with constructor parameters

// uint256 constant TARGET_HEALTH = 125 * WAD / 100; // 1.25 [wad]
// uint256 constant RESERVE_FACTOR = 2 * WAD / 100; // 0.02 [wad]
// uint256 constant MAX_DISCOUNT = 2 * WAD / 10; // 0.20 [wad]

// TODO: can this be configured inside of the constructor? 
uint32 constant ILK_COUNT = 8; 

contract Liquidation {  

    using SafeERC20 for IERC20; 
    using RoundedMath for uint256;

    error LiquidationThresholdCannotBeZero(uint256 liquidationThreshold); 
    error ExchangeRateCannotBeZero(uint256 exchangeRate); 
    error VaultIsNotUnsafe(uint256 healthRatio); 

    // --- parameters ---

    uint256 immutable TARGET_HEALTH; 
    uint256 immutable RESERVE_FACTOR; 
    uint256 immutable MAX_DISCOUNT; 

    // ilk specific variable
    uint64[ILK_COUNT] public liquidationThresholds; // [wad] indexed by ilkIndex

    address public immutable revenueRecipient; 
    
    IonPool public immutable ionPool;
    IReserveOracle public immutable reserveOracle; 
    IERC20 public immutable underlying; 

    struct LiquidateArgs {
        uint256 repay;
        uint256 gemOut;
        uint256 dart;
        uint256 fee; 
        uint256 price; 
    }

    // --- Events ---
    event Liquidate(address kpr, uint256 indexed repay, uint256 indexed gemOutLessFee, uint256 fee);

    constructor(
        address _ionPool, 
        address _reserveOracle, 
        address _revenueRecipient, 
        uint64[ILK_COUNT] memory _liquidationThresholds,
        uint256 _targetHealth, 
        uint256 _reserveFactor, 
        uint256 _maxDiscount 
        ) {
        ionPool = IonPool(_ionPool);
        reserveOracle = IReserveOracle(_reserveOracle); 
        revenueRecipient = _revenueRecipient;
        liquidationThresholds = _liquidationThresholds; 
        
        TARGET_HEALTH = _targetHealth; 
        RESERVE_FACTOR = _reserveFactor; 
        MAX_DISCOUNT = _maxDiscount; 

        underlying = ionPool.getUnderlying(); 
        underlying.approve(address(ionPool), type(uint256).max); // approve ionPool to transfer the underlying asset
    }

    /**
     * @dev internal helper function for liquidation math. Final repay amount 
     * NOTE: find better way to handle precision 
     * @param totalDebt [rad] this needs to be rad since repay can be set to totalDebt 
     * @param dust [ray]
     * @param collateral [ray] 
     * @param exchangeRate [ray] 
     * @param liquidationThreshold [ray]
     * @param discount [ray] 
     * @return repay [wad]  
     */
     // TODO: just get rid of this helper function 
    function _getRepayAmt(uint256 totalDebt, uint256 dust, uint256 collateral, uint256 exchangeRate, uint256 liquidationThreshold, uint256 discount)
        internal
        view
        returns (uint256 repay)
    {
        console.log("in get repay amt"); 
        // repayNum = (targetHealth * totalDebt - collateral * exchangeRate * liquidationThreshold)
        // [wad] * _scaleToRay([wad]) -  [wad] * [wad] * [wad]
        // repayDen = (targetHealth - (liquidationThreshold / (1 - discount)))
        // [wad] - ([wad] / (1 - [wad]))

        console.log("TARGET_HEALTH: ", TARGET_HEALTH); 
        console.log("totalDebt: ", totalDebt); 
        console.log("totalDebt scaled: ", totalDebt.scaleToRay(45)); 
        console.log("targetHealth * totalDebt: ", TARGET_HEALTH.roundedWadMul(totalDebt.scaleToWad(45)));  
        console.log("collateralValue: ", collateral.roundedWadMul(exchangeRate).roundedWadMul(liquidationThreshold)); 
        uint256 repayNum = TARGET_HEALTH.scaleToRay(18).roundedRayMul(totalDebt.scaleToRay(45)) - collateral.roundedRayMul(exchangeRate).roundedRayMul(liquidationThreshold); // [wad] 
        console.log("repayNum: ", repayNum); 
        uint256 repayDen = TARGET_HEALTH.scaleToRay(18) - liquidationThreshold.roundedRayDiv((RAY - discount)); // [wad] 
        console.log("repayDen: ", repayDen); 
        repay = repayNum.roundedRayDiv(repayDen).scaleToWad(27); // do all calculations in [ray] in convert to [wad] at the end 
        console.log("repay: ", repay); 
    }

    /**
     * @dev Executes collateral sale and repayment of debt by liquidators. 
     * NOTE: assumes that the kpr already has internal alleth
     *       and approved liq to move its alleth.
     */
    function liquidate(
        uint8 ilkIndex,
        address vault, // urn to be liquidated
        address kpr // receiver of collateral
    ) external {
        console.log("--- in liquidations --- "); 
        // --- Calculations ---

        LiquidateArgs memory liquidateArgs;

        // needs ink art rate 
        // TODO: multiple external calls vs. calling one getter that returns all 
        uint256 collateral = ionPool.collateral(ilkIndex, vault); 
        uint256 normalizedDebt = ionPool.normalizedDebt(ilkIndex, vault); 
        uint256 rate = ionPool.rate(ilkIndex); 
        uint256 dust = ionPool.dust(ilkIndex); 
       
        console.log("liqThres 0: ", liquidationThresholds[0]); 
        console.log("liqThres 1: ", liquidationThresholds[1]); 
        console.log("liqThres 2: ", liquidationThresholds[2]); 
        uint256 liquidationThreshold = liquidationThresholds[ilkIndex]; // []
        uint256 exchangeRate = reserveOracle.getExchangeRate(ilkIndex); // [ray] 
        
        if (exchangeRate == 0) {
            revert ExchangeRateCannotBeZero(exchangeRate); 
        }
        if (liquidationThreshold == 0) {
            revert LiquidationThresholdCannotBeZero(liquidationThreshold); 
        }

        /**
         * health score = (ink * spot) * mat) / (art * rate)
         * [wad] * [ray] * [ray] / ([wad] * [ray]) = [ray]
         */
        
        // healthScore = collateral * exchangeRate * liquidationThreshold / (normalized Debt * rate)
        //             = [wad] * [wad] * [wad] / ([wad] * [ray])   
        // the rate gets scaled to [wad] and the healthScore output should be in [wad] 
        console.log("collateral: ", collateral); 
        console.log("exchangeRate: ", exchangeRate); 
        console.log("liquidationThreshold: ", liquidationThreshold); 
        console.log("collateral * exchangeRate: ", collateral.roundedWadMul(exchangeRate)); 
        console.log("collateral * exchangeRate * liquidationThreshold: ", collateral.roundedWadMul(exchangeRate).roundedWadMul(liquidationThreshold));
        

        uint256 healthRatio = collateral.roundedWadMul(exchangeRate).roundedWadMul(liquidationThreshold); // [wad] * [wad] * [wad] = [wad] 
        healthRatio = healthRatio.roundedWadDiv(normalizedDebt).roundedWadDiv(rate.scaleToWad(27)); // [wad] / [wad] / [wad] = [wad] 
        
        console.log("healthRatio: ", healthRatio); 
        
        if (healthRatio >= WAD) {
            revert VaultIsNotUnsafe(healthRatio); 
        }

        uint256 discount = RESERVE_FACTOR + (WAD - healthRatio); // [ray] + ([ray] - [ray])
        discount = discount <= MAX_DISCOUNT ? discount : MAX_DISCOUNT; // cap discount to maxDiscount

        liquidateArgs.price = exchangeRate.wadMulUp((WAD - discount)); // [wad] ETH price per LST 
        console.log("collateral sale price: ", liquidateArgs.price); 

        liquidateArgs.repay = _getRepayAmt(normalizedDebt * rate, dust.scaleToRay(18), collateral.scaleToRay(18), exchangeRate.scaleToRay(18), liquidationThreshold.scaleToRay(18), discount.scaleToRay(18));
        console.log("repay: ", liquidateArgs.repay); 
        
        // liquidateArgs.dart = liquidateArgs.gemOut >= collateral ? normalizedDebt : liquidateArgs.repay / rate; // normalize the repay amount by rate to get the actual dart to frob
        // console.log("dart: ", liquidateArgs.dart); 

        // liquidateArgs.fee = liquidateArgs.gemOut * RESERVE_FACTOR / RAY; // [wad] * [ray] / [ray] = [wad]

        // --- Conditionals --- 
        
        // First branch: full liquidation 
        //    if repay > total debt, more debt needs to be paid off than available to go back to target health
        //    Move exactly all collateral and debt to the vow. 
        //    Keeper pays gas but is otherwise left untouched. 
        // Second branch: resulting debt is below dust 
        //    There is enough collateral to cover the debt and go back to target health, 
        //    but it would leave a debt amount less than dust. 
        //    Force keeper to pay off all debt including dust and readjust the amount of collateral to sell. 
        //    Resulting debt is zero. 
        // Third branch: soft liquidation to target health ratio 
        //    There is enough collateral to be sold to pay off debt. 
        //    The resulting health ratio equals targetHealthRatio. 
        
        // NOTE: could also add gemOut > collateral check
        if (liquidateArgs.repay > normalizedDebt.rayMulDown(rate)) { // [wad] * [ray] / [ray] = [wad] 
            liquidateArgs.dart = normalizedDebt; 
            liquidateArgs.gemOut = collateral; 
            ionPool.confiscateVault(ilkIndex, vault, address(this), address(this), -int256(liquidateArgs.gemOut), -int256(liquidateArgs.dart));     
            
            // NOTE: Echidna Assertions 
            console.log("PROTOCOL LIQUIDATION"); 
            assert(ionPool.normalizedDebt(ilkIndex, vault) == 0);
            assert(ionPool.collateral(ilkIndex, vault) == 0);

            // TODO: emit protocol liquidation event 
            return; 
        } else if (normalizedDebt * rate - liquidateArgs.repay < dust) {
            // NOTE: we transfer with repay, pay down with dart  
            liquidateArgs.repay = normalizedDebt.rayMulDown(rate); // [wad] * [ray] / [ray] = [wad] pay off all debt  
            liquidateArgs.dart = normalizedDebt; 
            liquidateArgs.gemOut = liquidateArgs.repay.wadDivDown(liquidateArgs.price); // readjust amount of collateral to sell 
        
            // NOTE: Echidna Assertions 
            console.log("DUST LIQUIDATION"); 
            assert(ionPool.normalizedDebt(ilkIndex, vault) == 0); 
        } else {
            // repay stays unchanged  
            liquidateArgs.dart = liquidateArgs.repay.rayDivDown(rate); // normalized  
            liquidateArgs.gemOut = liquidateArgs.repay.wadDivDown(liquidateArgs.price); // readjust amount of collateral to sell 
            
            // NOTE: healthRatio is 1.25 
            uint256 newHealthRatio = (collateral - liquidateArgs.gemOut).roundedWadMul(exchangeRate).roundedWadMul(liquidationThreshold); // [wad] * [wad] * [wad] = [wad] 
            newHealthRatio = newHealthRatio.roundedWadDiv(normalizedDebt - liquidateArgs.dart).roundedWadDiv(rate.scaleToWad(27)); // [wad] / [wad] / [wad] = [wad] 
            console.log("PARTIAL LIQUIDATION"); 
            console.log("newHealthRatio: ", newHealthRatio); 
            assert(newHealthRatio >= 1.24 ether && newHealthRatio < 1.26 ether); 
        }
        
        // --- For First Branch and Second Branch
        // calculate fee
        liquidateArgs.fee = liquidateArgs.gemOut.rayMulUp(RESERVE_FACTOR); // [wad] * [ray] / [ray] = [wad] 
        // transfer WETH from keeper to this contract 
        underlying.safeTransferFrom(msg.sender, address(this), liquidateArgs.repay); 
        // take the debt to pay off and the collateral to sell from the vault 
        // TODO: check for integer overflows 
        ionPool.confiscateVault(ilkIndex, vault, address(this), address(this), -int256(liquidateArgs.gemOut), -int256(liquidateArgs.dart)); 
        // pay off this contract's debt 
        ionPool.repayBadDebt(address(this), liquidateArgs.repay); 
        // send fee to the revenueRecipient 
        ionPool.transferGem(ilkIndex, address(this), revenueRecipient, liquidateArgs.fee); 
        // send the collateral sold to the keeper 
        ionPool.transferGem(ilkIndex, address(this), kpr, liquidateArgs.gemOut - liquidateArgs.fee); 
        
        emit Liquidate(kpr, liquidateArgs.repay, liquidateArgs.gemOut - liquidateArgs.fee, liquidateArgs.fee); 
        
        // // --- Storage Updates ---

        // // move weth from kpr to liq
        // underlying.safeTransferFrom(kpr, address(this), liquidateArgs.repay);

        // // confiscate part of the urn
        // //  1. move art into liq's sin (unbacked debt) 
        // //  2. move ink into liq's gem (unlocked collateral)
        // //  NOTE: if all collateral is sold (gemOut == ink), then (dart = art)
        // //        this confiscates all debt. What doesn't get paid off by liquidation gets passed to the vow.
        // //        if not all collateral is sold (gemOut < ink), confiscate only the debt to be paid off

        // require(int256(liquidateArgs.gemOut) >= 0 && int256(liquidateArgs.dart) >= 0, "Liq/dart-overflow");

        // // moves the art into liq's sin and ink into liq's gem
        // ionPool.confiscateVault(ilkIndex, vault, address(this), address(this), -int256(liquidateArgs.gemOut), -int256(liquidateArgs.dart));

        // // give the unlocked collateral minus the fee to the kpr
        // ionPool.transferGem(ilkIndex, address(this), kpr, liquidateArgs.gemOut - liquidateArgs.fee); 

        // // reserve fee: give the fee in collateral to the revenueRecipient
        // ionPool.transferGem(ilkIndex, address(this), revenueRecipient, liquidateArgs.fee);

        // // payback liquidation's unbacked debt with the underlying ERC20 
        // // if all collateral was sold and debt remains, this contract keeps the sin
        // ionPool.repayBadDebt(liquidateArgs.repay); 

        // emit Liquidate(kpr, liquidateArgs.repay, liquidateArgs.gemOut - liquidateArgs.fee, liquidateArgs.fee);
    }
}
