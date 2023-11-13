// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { WadRayMath, RAY } from "./libraries/math/WadRayMath.sol";
import { IonPool } from "src/IonPool.sol";
import { ReserveOracle } from "src/oracles/reserve/ReserveOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract Liquidation {
    using SafeERC20 for IERC20;
    using WadRayMath for uint256;
    using SafeCast for uint256;

    error LiquidationThresholdCannotBeZero();
    error ExchangeRateCannotBeZero();
    error VaultIsNotUnsafe(uint256 healthRatio);
    error InvalidReserveOraclesLength(uint256 length);
    error InvalidLiquidationThresholdsLength(uint256 length);

    // --- parameters ---

    uint256 public immutable TARGET_HEALTH; // [ray] ex) 1.25e27 is 125%
    uint256 public immutable BASE_DISCOUNT; // [ray] ex) 0.02e27 is 2%
    uint256 public immutable MAX_DISCOUNT; // [ray] ex) 0.2e27 is 20%

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
    event Liquidate(address indexed kpr, uint8 indexed ilkIndex, uint256 repay, uint256 gemOut);

    constructor(
        address _ionPool,
        address _protocol,
        address[] memory _reserveOracles,
        uint256[] memory _liquidationThresholds,
        uint256 _targetHealth,
        uint256 _reserveFactor,
        uint256 _maxDiscount
    ) {
        IonPool ionPool_ = IonPool(_ionPool);
        POOL = ionPool_;
        PROTOCOL = _protocol;

        uint256 ilkCount = POOL.ilkCount();
        if (_reserveOracles.length != ilkCount) {
            revert InvalidReserveOraclesLength(_reserveOracles.length);
        }
        if (_liquidationThresholds.length != ilkCount) {
            revert InvalidLiquidationThresholdsLength(_liquidationThresholds.length);
        }

        TARGET_HEALTH = _targetHealth;
        BASE_DISCOUNT = _reserveFactor;
        MAX_DISCOUNT = _maxDiscount;

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

    /**
     * @notice Returns the exchange rate and liquidation threshold for the given ilkIndex.
     */
    function _getExchangeRateAndLiquidationThreshold(uint8 ilkIndex)
        internal
        view
        returns (uint256 liquidationThreshold, uint256 exchangeRate)
    {
        address reserveOracle;
        if (ilkIndex == 0) {
            reserveOracle = RESERVE_ORACLE_0;
            liquidationThreshold = LIQUIDATION_THRESHOLD_0;
        } else if (ilkIndex == 1) {
            reserveOracle = RESERVE_ORACLE_1;
            liquidationThreshold = LIQUIDATION_THRESHOLD_1;
        } else if (ilkIndex == 2) {
            reserveOracle = RESERVE_ORACLE_2;
            liquidationThreshold = LIQUIDATION_THRESHOLD_2;
        }
        // exchangeRate is reported in uint72 in [wad], but should be converted to uint256 [ray]
        exchangeRate = ReserveOracle(reserveOracle).currentExchangeRate();
        exchangeRate = uint256(exchangeRate).scaleUpToRay(18);
    }

    /**
     * @notice Internal helper function for calculating the repay amount
     * @param debtValue [rad] totalDebt
     * @param collateralValue [rad] collateral * exchangeRate * liquidationThreshold
     * @param liquidationThreshold [ray]
     * @param discount [ray]
     * @return repay [rad]
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

        // round up repay in protocol favor for safer post-liquidation position
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
     * @notice Executes collateral sale and repayment of debt by liquidators.
     * TODO: all eth?
     * @dev This function assumes that the `kpr` already has internal alleth
     *      and approved liq to move its alleth.
     * @param ilkIndex index of the collateral in IonPool
     * @param vault the position to be liquidated
     * @param kpr payer of the debt and receiver of the collateral
     */
    function liquidate(uint8 ilkIndex, address vault, address kpr) external {
        LiquidateArgs memory liquidateArgs;

        (uint256 collateral, uint256 normalizedDebt) = POOL.vault(ilkIndex, vault);
        uint256 rate = POOL.rate(ilkIndex);

        (uint256 liquidationThreshold, uint256 exchangeRate) = _getExchangeRateAndLiquidationThreshold(ilkIndex);

        if (exchangeRate == 0) {
            revert ExchangeRateCannotBeZero();
        }
        if (liquidationThreshold == 0) {
            revert LiquidationThresholdCannotBeZero();
        }

        // collateralValue = collateral * exchangeRate * liquidationThreshold
        // debtValue = normalizedDebt * rate
        // healthRatio = collateralValue / debtValue
        // collateralValue = [wad] * [ray] * [ray] / RAY = [rad]
        // debtValue = [wad] * [ray] = [rad]
        // healthRatio = [rad] * RAY / [rad] = [ray]
        // round down in protocol favor
        uint256 collateralValue = (collateral * exchangeRate).rayMulDown(liquidationThreshold);
        {
            uint256 healthRatio = collateralValue.rayDivDown(normalizedDebt * rate); // round down in protocol favor
            if (healthRatio >= RAY) {
                revert VaultIsNotUnsafe(healthRatio);
            }

            uint256 discount = BASE_DISCOUNT + (RAY - healthRatio); // [ray] + ([ray] - [ray])
            discount = discount <= MAX_DISCOUNT ? discount : MAX_DISCOUNT; // cap discount to maxDiscount
            liquidateArgs.price = exchangeRate.rayMulUp(RAY - discount); // ETH price per LST, round up in protocol
                // favor
            liquidateArgs.repay = _getRepayAmt(normalizedDebt * rate, collateralValue, liquidationThreshold, discount);
        }

        // First branch: protocol liquidation
        //    if repay > total debt, more debt needs to be paid off than available to go back to target health
        //    Move exactly all collateral and debt to the protocol.
        //    Keeper pays gas but is otherwise left untouched.
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
            emit Liquidate(kpr, ilkIndex, liquidateArgs.dart, liquidateArgs.gemOut);
            return; // early return
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

        // below code only reached for dust or partial liquidations

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

        emit Liquidate(kpr, ilkIndex, liquidateArgs.dart, liquidateArgs.gemOut);
    }
}
