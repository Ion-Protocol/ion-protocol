pragma solidity ^0.8.13;

import {IonPool} from "src//IonPool.sol"; 
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";

// TODO: import instead when ReserveOracle is finished
interface IReserveOracle {
    function getExchangeRate(uint ilkId) external view returns (uint256 exchangeRate); 
}

contract Liquidation is Pausable {  

    error LiquidationThresholdCannotBeZero(uint256 liquidationThreshold); 
    error ExchangeRateCannotBeZero(uint256 exchangeRate); 
    error VaultIsNotUnsafe(uint256 healthRatio); 

    // --- Math ---

    uint256 constant RAY = 10 ** 27;
    uint256 constant WAD = 10 ** 18;

    // --- parameters ---

    // pack global variables into uint256?
    uint64 public immutable targetHealth; // uint64 [wad] 
    uint64 public immutable reserveFactor; // uint64 [wad]
    uint64 public immutable maxDiscount; // uint64 [wad] 

    // ilk specific variable
    uint64[] public immutable liquidationThresholds; // [wad] indexed by ilkId

    address public immutable revenueRecipient; 
    
    IonPool public immutable ionPool;
    IReserveOracle public immutable reserveOracle; 

    struct TakeArgs {
        uint256 repay;
        uint256 gemOut;
        uint256 dart;
    }

    // --- Events ---
    event Take(address kpr, uint256 indexed repay, uint256 indexed gemOutLessFee, uint256 fee);

    constructor(address _ionPool, address _reserveOracle, address _revenueRecipient) {
        ionPool = IonPool(_ionPool);
        reserveOracle = IReserveOracle(_reserveOracle); 
        revenueRecipient = _revenueRecipient;

        // initial parameters
        targetHealth = 125 * WAD / 100; // 1.25 [wad]
        reserveFactor = 2 * WAD / 100; // 0.02 [wad]
        maxDiscount = 2 * WAD / 10; // 0.20 [wad]
    }

    function _getRepayAmt(uint256 discount, uint256 tab, uint256 ink, uint256 spot, uint256 mat, uint256 dust)
        internal
        view
        returns (uint256 repay, uint256 gemOut)
    {
        {
            // [wad] * [ray] / RAY * [ray] = [rad]
            // [wad] * [ray] / RAY * [ray] = [rad]
            // [rad] - [rad] = [rad]
            uint256 repayNum = (tab / RAY * targetHealth - ink * spot / RAY * mat); // [rad]
            uint256 repayDen = targetHealth - (mat * RAY / (RAY - discount)); // [ray] - ([ray] * [ray] / [ray]) = [ray]
            repay = repayNum / repayDen * RAY; // [rad] / [ray] * RAY = [rad]

            // first branch: full liquidation
            //   more debt needs to be paid off than available to go back to target health,
            //   so all collateral is sold off and the alleth repay amount is readjusted
            // second branch: resulting debt below dust
            //   there is enough collateral to cover the debt and go back to target health,
            //   but it would leave a debt amount less than dust. So just pay off all dust
            //   and readjust the collateral
            // third branch: soft liquidation to target health ratio

            if (repay > tab) {
                gemOut = ink; // [wad] sell all collateral
                // RAY * RAY / RAY * WAD = RAD
                repay = (RAY - discount) * spot / RAY * gemOut; // [wad] * [ray] / RAY * [ray] = [rad]
            } else if (tab - repay < dust) {
                repay = tab;
                // gemOut = allETH / (ETH / LST)
                // gemOut = repay (allETH amount) / discounted price
                //        = repay / (spot * (1 - discount))
                //        = [rad] / ([ray] * [ray] / RAY) = [wad]
                gemOut = repay / (spot * (RAY - discount) / RAY);
            } else {
                // repay stays same
                gemOut = repay / (spot * (RAY - discount) / RAY);
            }
        }
    }

    /**
     * @dev Executes collateral sale and repayment of debt by liquidators. 
     * NOTE: assumes that the kpr already has internal alleth
     *       and approved liq to move its alleth.
     */
    function liquidate(
        uint ilkId,
        address vault, // urn to be liquidated
        address kpr // receiver of collateral
    ) external {
        
        // --- Calculations ---

        LiquidateArgs memory liquidateArgs;

        // needs ink art rate 
        (uint256 collateral, uint256 normalizedDebt) = ionPool.vaults(ilkId, vault);
        (, uint104 rate, , , , uint256 dust) = ionPool.ilks(ilkId); // less reads? 
        uint64 liquidationThreshold = liquidationThresholds[ilkId]; // []
        uint64 exchangeRate = reserveOracle.getExchangeRate(ilkId); // [ray] 
        
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
        
        uint256 healthRatio = exchangeRate * liquidationThreshold / normalizedDebt * collateral / rate; 
        
        if (healthRatio < HEALTH_RATIO_ONE) {
            revert VaultIsNotUnsafe(healthRatio); 
        }

        uint256 discount = reserveFactor + (HEALTH_RATIO_ONE - healthRatio); // [ray] + ([ray] - [ray])
        discount = discount <= maxDiscount ? discount : maxDiscount; // cap discount to maxDiscount

        // [rad] [wad]
        (liquidateArgs.repay, liquidateArgs.gemOut) = _getRepayAmt(discount, normalizedDebt * rate, collateral, exchangeRate, liquidationThreshold, dust);
        
        liquidateArgs.dart = liquidateArgs.gemOut >= collateral ? normalizedDebt : liquidateArgs.repay / rate; // normalize the repay amount by rate to get the actual dart to frob

        uint256 fee = liquidateArgs.gemOut * reserveFactor / RAY; // [wad] * [ray] / [ray] = [wad]

        // --- Storage Updates ---

        // move weth from kpr to liq
        vat.move(kpr, address(this), liquidateArgs.repay);

        // confiscate part of the urn
        //  1. move art into liq's sin (unbacked debt) TODO: move into vow's sin 
        //  2. move ink into liq's gem (unlocked collateral)
        //  NOTE: if all collateral is sold (gemOut == ink), then (dart = art)
        //        this confiscates all debt. What doesn't get paid off by liquidation gets passed to the vow.
        //        if not all collateral is sold (gemOut < ink), confiscate only the debt to be paid off

        require(int256(liquidateArgs.gemOut) >= 0 && int256(liquidateArgs.dart) >= 0, "Liq/dart-overflow");

        // moves the art into liq's sin and ink into liq's gem
        ionPool.confiscateVault(ilkIndex, vault, address(this), address(this), -int256(liquidateArgs.gemOut), -int256(liquidateArgs.dart));

        // give the unlocked collateral minus the fee to the kpr
        ionPool.transferGem(ilkIndex, address(this), kpr, liquidateArgs.gemOut - fee); 

        // reserve fee: give the fee in collateral to the revenueRecipient
        ionPool.transferGem(ilkIndex, address(this), revenueRecipient, fee);

        // payback liquidation's unbacked debt with weth
        // if all collateral was sold and debt remains, this contract keeps the sin
        ionPool.repayBadDebt(liquidateArgs.repay, address(this)); 

        emit Liquidate(kpr, liquidateArgs.repay, liquidateArgs.gemOut - fee, fee);
    }
}
