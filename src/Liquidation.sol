// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "./IonPool.sol";
import { WadRayMath, RAY } from "./libraries/math/WadRayMath.sol";
import { ReserveOracle } from "./oracles/reserve/ReserveOracle.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice The liquidation module for the `IonPool`.
 * 
 * Liquidations at Ion operate a little differently than traditional liquidation schemes. Usually, liquidations are a function of the market price of an asset. However, the liquidation module is function of the reserve oracle price which reflects a rate based on **beacon-chain balances**. 
 * 
 * There are 3 different types of liquidations that can take place:
 * - Partial Liquidation: The liquidator pays off a portion of the debt and receives a portion of the collateral.
 * - Dust Liquidation: The liquidator pays off all of the debt and receives some or all of the collateral. 
 * - Protocol Liquidation: The liquidator transfers the position's debt and collateral onto the protocol's balance sheet.
 * 
 * NOTE: Protocol liqudations are unlikely to ever be executed since there is
 * no profit incentive for a liquidator to do so. They exist solely as a
 * fallback if a liquidator were to ever execute a liquidation onto a vault that
 * had fallen into bad debt.
 * 
 * @custom:security-contact security@molecularlabs.io
 */
contract Liquidation {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using SafeCast for uint256;

    error ExchangeRateCannotBeZero();
    error VaultIsNotUnsafe(uint256 healthRatio);

    error InvalidReserveOraclesLength(uint256 length);
    error InvalidLiquidationThresholdsLength(uint256 length);
    error InvalidMaxDiscountsLength(uint256 length);
    error InvalidTargetHealth(uint256 targetHealth);
    error InvalidLiquidationThreshold(uint256 liquidationThreshold);
    error InvalidMaxDiscount(uint256 maxDiscount);

    // --- Parameters ---

    uint256 public immutable TARGET_HEALTH; // [ray] ex) 1.25e27 is 125%
    uint256 public immutable BASE_DISCOUNT; // [ray] ex) 0.02e27 is 2%

    uint256 public immutable MAX_DISCOUNT_0; // [ray] ex) 0.2e27 is 20%
    uint256 public immutable MAX_DISCOUNT_1;
    uint256 public immutable MAX_DISCOUNT_2;

    // liquidation thresholds
    uint256 public immutable LIQUIDATION_THRESHOLD_0; // [ray] liquidation threshold for ilkIndex 0
    uint256 public immutable LIQUIDATION_THRESHOLD_1; // [ray]
    uint256 public immutable LIQUIDATION_THRESHOLD_2; // [ray]

    // exchange rates
    address public immutable RESERVE_ORACLE_0; // reserve oracle providing exchange rate for ilkIndex 0
    address public immutable RESERVE_ORACLE_1;
    address public immutable RESERVE_ORACLE_2;

    address public immutable PROTOCOL; // receives confiscated vault debt and collateral

    IonPool public immutable POOL;
    IERC20 public immutable UNDERLYING;

    // --- Events ---
    event Liquidate(
        address indexed initiator, address indexed kpr, uint8 indexed ilkIndex, uint256 repay, uint256 gemOut
    );

    /**
     * @notice Creates a new `Liquidation` instance.
     * @param _ionPool The address of the `IonPool` contract.
     * @param _protocol The address that will represent the protocol balance
     * sheet (for protocol liquidation purposes).
     * @param _reserveOracles List of reserve oracle addresses for each ilk.
     * @param _liquidationThresholds List of liquidation thresholds for each
     * ilk.
     * @param _targetHealth The target health ratio for positions.
     * @param _reserveFactor Base discount for collateral.
     * @param _maxDiscounts List of max discounts for each ilk.
     */
    constructor(
        address _ionPool,
        address _protocol,
        address[] memory _reserveOracles,
        uint256[] memory _liquidationThresholds,
        uint256 _targetHealth,
        uint256 _reserveFactor,
        uint256[] memory _maxDiscounts
    ) {
        IonPool ionPool_ = IonPool(_ionPool);
        POOL = ionPool_;
        PROTOCOL = _protocol;

        uint256 ilkCount = POOL.ilkCount();

        uint256 maxDiscountsLength = _maxDiscounts.length;
        if (maxDiscountsLength != ilkCount) {
            revert InvalidMaxDiscountsLength(_maxDiscounts.length);
        }

        if (_reserveOracles.length != ilkCount) {
            revert InvalidReserveOraclesLength(_reserveOracles.length);
        }

        uint256 liquidationThresholdsLength = _liquidationThresholds.length;
        if (liquidationThresholdsLength != ilkCount) {
            revert InvalidLiquidationThresholdsLength(_liquidationThresholds.length);
        }

        for (uint256 i = 0; i < maxDiscountsLength;) {
            if (_maxDiscounts[i] >= RAY) revert InvalidMaxDiscount(_maxDiscounts[i]);

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }

        for (uint256 i = 0; i < liquidationThresholdsLength;) {
            if (_liquidationThresholds[i] == 0) revert InvalidLiquidationThreshold(_liquidationThresholds[i]);

            // This invariant must hold otherwise all liquidations will revert
            // when discount == configs.maxDiscount within the _getRepayAmt
            // function.
            if (_targetHealth < _liquidationThresholds[i].rayDivUp(RAY - _maxDiscounts[i])) {
                revert InvalidTargetHealth(_targetHealth);
            }

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }

        if (_targetHealth < RAY) revert InvalidTargetHealth(_targetHealth);

        TARGET_HEALTH = _targetHealth;
        BASE_DISCOUNT = _reserveFactor;

        MAX_DISCOUNT_0 = _maxDiscounts[0];
        MAX_DISCOUNT_1 = _maxDiscounts[1];
        MAX_DISCOUNT_2 = _maxDiscounts[2];

        IERC20 underlying = ionPool_.underlying();
        underlying.approve(address(ionPool_), type(uint256).max); // approve ionPool to transfer the UNDERLYING asset
        UNDERLYING = underlying;

        LIQUIDATION_THRESHOLD_0 = _liquidationThresholds[0];
        LIQUIDATION_THRESHOLD_1 = _liquidationThresholds[1];
        LIQUIDATION_THRESHOLD_2 = _liquidationThresholds[2];

        RESERVE_ORACLE_0 = _reserveOracles[0];
        RESERVE_ORACLE_1 = _reserveOracles[1];
        RESERVE_ORACLE_2 = _reserveOracles[2];
    }

    struct Configs {
        uint256 liquidationThreshold;
        uint256 maxDiscount;
        address reserveOracle;
    }

    /**
     * @notice Returns the exchange rate, liquidation threshold, and max
     * discount for the given ilk.
     * @param ilkIndex The index of the ilk.
     */
    function _getConfigs(uint8 ilkIndex)
        internal
        view
        returns (Configs memory configs)
    {
        if (ilkIndex == 0) {
            configs.reserveOracle = RESERVE_ORACLE_0;
            configs.liquidationThreshold = LIQUIDATION_THRESHOLD_0;
            configs.maxDiscount = MAX_DISCOUNT_0;
        } else if (ilkIndex == 1) {
            configs.reserveOracle = RESERVE_ORACLE_1;
            configs.liquidationThreshold = LIQUIDATION_THRESHOLD_1;
            configs.maxDiscount = MAX_DISCOUNT_1;
        } else if (ilkIndex == 2) {
            configs.reserveOracle = RESERVE_ORACLE_2;
            configs.liquidationThreshold = LIQUIDATION_THRESHOLD_2;
            configs.maxDiscount = MAX_DISCOUNT_2;
        }
    }

    /**
     * @notice If liquidation is possible, returns the amount of WETH necessary
     * to liquidate a vault.
     * @param ilkIndex The index of the ilk.
     * @param vault The address of the vault.
     * @return repay The amount of WETH necessary to liquidate the vault.
     */
    function getRepayAmt(uint8 ilkIndex, address vault) public view returns (uint256 repay) {
        Configs memory configs = _getConfigs(ilkIndex);

        // exchangeRate is reported in uint72 in [wad], but should be converted to uint256 [ray]
        uint256 exchangeRate = uint256(ReserveOracle(configs.reserveOracle).currentExchangeRate()).scaleUpToRay(18);
        (uint256 collateral, uint256 normalizedDebt) = POOL.vault(ilkIndex, vault);
        uint256 rate = POOL.rate(ilkIndex);

        if (exchangeRate == 0) {
            revert ExchangeRateCannotBeZero();
        }

        // collateralValue = collateral * exchangeRate * liquidationThreshold
        // debtValue = normalizedDebt * rate
        // healthRatio = collateralValue / debtValue
        // collateralValue = [wad] * [ray] * [ray] / RAY = [rad]
        // debtValue = [wad] * [ray] = [rad]
        // healthRatio = [rad] * RAY / [rad] = [ray]
        // round down in protocol favor
        uint256 collateralValue = (collateral * exchangeRate).rayMulDown(configs.liquidationThreshold);
    
        uint256 healthRatio = collateralValue.rayDivDown(normalizedDebt * rate); // round down in protocol favor
        if (healthRatio >= RAY) {
            revert VaultIsNotUnsafe(healthRatio);
        }

        uint256 discount = BASE_DISCOUNT + (RAY - healthRatio); // [ray] + ([ray] - [ray])
        discount = discount <= configs.maxDiscount ? discount : configs.maxDiscount; // cap discount to maxDiscount favor
        uint256 repayRad = _getRepayAmt(normalizedDebt * rate, collateralValue, configs.liquidationThreshold, discount);

        repay = (repayRad / RAY);
        if (repayRad % RAY > 0) ++repay; 
    }

    /**
     * @notice Internal helper function for calculating the repay amount.
     * @param debtValue The total debt. [RAD]
     * @param collateralValue Calculated with collateral * exchangeRate * liquidationThreshold. [RAD]
     * @param liquidationThreshold Ratio at which liquidation can occur. [RAY]
     * @param discount The discount from the exchange rate at which the collateral is sold. [RAY]
     * @return repay The amount of WETH necessary to liquidate the vault. [RAD]
     */
    function _getRepayAmt(
        uint256 debtValue,
        uint256 collateralValue,
        uint256 liquidationThreshold,
        uint256 discount
    )
        internal
        view
        returns (uint256 repay)
    {
        // repayNum = (targetHealth * totalDebt - collateral * exchangeRate * liquidationThreshold)
        // repayDen = (targetHealth - (liquidationThreshold / (1 - discount)))
        // repay = repayNum / repayDen

        // Round up repay in protocol favor for safer post-liquidation position
        // This will never underflow because at this point we know health ratio
        // is less than 1, which means that collateralValue < debtValue.
        uint256 repayNum = debtValue.rayMulUp(TARGET_HEALTH) - collateralValue; // [rad] - [rad] = [rad]
        uint256 repayDen = TARGET_HEALTH - liquidationThreshold.rayDivUp(RAY - discount); // [ray]
        repay = repayNum.rayDivUp(repayDen); // [rad] * RAY / [ray] = [rad]
    }

    struct LiquidateArgs {
        uint256 repay;
        uint256 gemOut;
        uint256 dart;
        uint256 fee;
        uint256 price;
    }

    /**
     * @notice Closes an unhealthy position on `IonPool`.
     * @param ilkIndex The index of the collateral.
     * @param vault The position to be liquidated.
     * @param kpr Receiver of the collateral.
     * @return repayAmount The amount of WETH paid to close the position.
     * @return gemOut The amount of collateral received from the liquidation.
     */
    function liquidate(uint8 ilkIndex, address vault, address kpr) external returns (uint256 repayAmount, uint256 gemOut) {
        LiquidateArgs memory liquidateArgs;

        Configs memory configs = _getConfigs(ilkIndex);

        // exchangeRate is reported in uint72 in [wad], but should be converted to uint256 [ray]
        uint256 exchangeRate = ReserveOracle(configs.reserveOracle).currentExchangeRate().scaleUpToRay(18);
        (uint256 collateral, uint256 normalizedDebt) = POOL.vault(ilkIndex, vault);
        uint256 rate = POOL.rate(ilkIndex);

        if (exchangeRate == 0) {
            revert ExchangeRateCannotBeZero();
        }

        // collateralValue = collateral * exchangeRate * liquidationThreshold
        // debtValue = normalizedDebt * rate
        // healthRatio = collateralValue / debtValue
        // collateralValue = [wad] * [ray] * [ray] / RAY = [rad]
        // debtValue = [wad] * [ray] = [rad]
        // healthRatio = [rad] * RAY / [rad] = [ray]
        // round down in protocol favor
        uint256 collateralValue = (collateral * exchangeRate).rayMulDown(configs.liquidationThreshold);
        {
            uint256 healthRatio = collateralValue.rayDivDown(normalizedDebt * rate); // round down in protocol favor
            if (healthRatio >= RAY) {
                revert VaultIsNotUnsafe(healthRatio);
            }

            uint256 discount = BASE_DISCOUNT + (RAY - healthRatio); // [ray] + ([ray] - [ray])
            discount = discount <= configs.maxDiscount ? discount : configs.maxDiscount; // cap discount to maxDiscount
            liquidateArgs.price = exchangeRate.rayMulUp(RAY - discount); // ETH price per LST, round up in protocol
                // favor
            liquidateArgs.repay =
                _getRepayAmt(normalizedDebt * rate, collateralValue, configs.liquidationThreshold, discount);
        }

        // First branch: protocol liquidation
        //    if repay > total debt, more debt needs to be paid off than available to go back to target health
        //    Move exactly all collateral and debt to the protocol.
        // Second branch: resulting debt is below dust
        //    There is enough collateral to cover the debt and go back to target health,
        //    but it would leave a debt amount less than dust.
        //    Force keeper to pay off all debt including dust and readjust the amount of collateral to sell.
        //    Resulting debt should always be zero.
        // Third branch: partial liquidation to target health ratio
        //    There is enough collateral to be sold to pay off debt.
        //    Liquidator pays portion of the debt and receives collateral.
        //    The resulting health ratio should equal target health.
        if (liquidateArgs.repay > normalizedDebt * rate) {
            // [rad] > [rad]
            liquidateArgs.dart = normalizedDebt; // [wad]
            liquidateArgs.gemOut = collateral; // [wad]
            POOL.confiscateVault(
                ilkIndex, vault, PROTOCOL, PROTOCOL, -int256(liquidateArgs.gemOut), -int256(liquidateArgs.dart)
            );
            emit Liquidate(msg.sender, kpr, ilkIndex, liquidateArgs.dart, liquidateArgs.gemOut);
            return (0, 0); // early return
        } else if (normalizedDebt * rate - liquidateArgs.repay < POOL.dust(ilkIndex)) {
            // [rad] - [rad] < [rad]
            liquidateArgs.repay = normalizedDebt * rate; // bound repay to total debt
            liquidateArgs.dart = normalizedDebt; // pay off all debt including dust
            liquidateArgs.gemOut = normalizedDebt * rate / liquidateArgs.price; // round down in protocol favor
        } else {
            // if (normalizedDebt * rate - liquidateArgs.repay >= dust) do partial liquidation
            // round up in protocol favor
            liquidateArgs.dart = liquidateArgs.repay / rate; // [rad] / [ray] = [wad]
            if (liquidateArgs.repay % rate > 0) ++liquidateArgs.dart; // round up in protocol favor
            // round down in protocol favor
            liquidateArgs.gemOut = liquidateArgs.repay / liquidateArgs.price; // readjust amount of collateral
            liquidateArgs.repay = liquidateArgs.dart * rate; // 27 decimals precision loss on original repay
        }

        // below code is only reached for dust or partial liquidations

        // exact amount to be transferred in `_transferWeth`
        uint256 transferAmt = (liquidateArgs.repay / RAY);
        if (liquidateArgs.repay % RAY > 0) ++transferAmt; // round up in protocol favor

        // transfer WETH from keeper to this contract
        UNDERLYING.safeTransferFrom(msg.sender, address(this), transferAmt);

        // take the debt to pay off and the collateral to sell from the vault
        // kpr gets the gemOut
        POOL.confiscateVault(
            ilkIndex, vault, kpr, address(this), -(liquidateArgs.gemOut.toInt256()), -(liquidateArgs.dart.toInt256())
        );

        // pay off the unbacked debt
        POOL.repayBadDebt(address(this), liquidateArgs.repay);

        emit Liquidate(msg.sender, kpr, ilkIndex, liquidateArgs.dart, liquidateArgs.gemOut);

        return (liquidateArgs.repay, liquidateArgs.gemOut);
    }
}
