// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "./IonPool.sol";
import { IWeEth, IStaderStakePoolsManager, ISwEth } from "./interfaces/ProviderInterfaces.sol";
import { IYieldOracle } from "./interfaces/IYieldOracle.sol";

import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// historicalExchangeRates can be thought of as a matrix of past exchange rates by collateral types. With a uint64 type
// storing exchange rates, 4 can be stored in one storage slot. So each day will consume ceil(ILK_COUNT / 4) storage
// slots.
//
//  look back days  | storage slot  ||                             data
//
//                  |                  256             172             128              64              0
//                  |               ||  |     ilk_4     |     ilk_3     |     ilk_2     |     ilk_1     |
//        1         |     n + 0     ||  |               |               |               |               |
//        2         |     n + 1     ||  |               |               |               |               |
//       ...        |    n + ...    ||  |               |               |               |               |
//        n         |     n + n     ||  |               |               |               |               |
//
// A uint64 has the capacity to store up to around ~18e18 which is more than enough to fit an exchange rate that only
// ever hovers around 1e18.

uint8 constant APY_PRECISION = 8;
uint8 constant PROVIDER_PRECISION = 18;

uint32 constant LOOK_BACK = 7;
uint256 constant PERIODS = 365 * (10 ** APY_PRECISION) / LOOK_BACK; // 52.142... eAPY_PRECISION
uint32 constant ILK_COUNT = 3;
// Seconds in 23.5 hours. This will allow for updates around the same time of day
uint256 constant UPDATE_LOCK_LENGTH = 84_600;

/**
 * @notice An on-chain oracle that provides the APY for each collateral type.
 *
 * @dev This contract stores a history of the exchange rates of each collateral
 * for the past `LOOK_BACK` days. Every time that `updateAll()` is called, it
 * will update the value at `currentIndex` in the `historicalExchangeRates` with the
 * current exchange rate and it will also calculate the APY for each collateral
 * type based on the data currently in the buffer. The APY is calculated by
 * taking the difference between the new element being added and the element
 * being replaced. This provides a growth amount of `LOOK_BACK` days. This value
 * is then projected out to a year.
 *
 * Similar to the `InterestRate` module, as the amount of collaterals added to
 * the market increases, storage reads during interest accrual can become
 * prohibitively expensive. Therefore, this contract is heavily optimized at the
 * unfortunate cost of code-complexity.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract YieldOracle is IYieldOracle, Ownable2Step {
    using Math for uint256;
    using SafeCast for uint256;

    // --- Errors ---

    error InvalidExchangeRate(uint256 ilkIndex);
    error InvalidIlkIndex(uint256 ilkIndex);
    error AlreadyUpdated();

    // --- Events ---

    event ApyUpdate(uint256 indexed ilkIndex, uint256 newApy);

    uint32[ILK_COUNT] public apys;

    uint64[ILK_COUNT][LOOK_BACK] public historicalExchangeRates;
    address public immutable ADDRESS0;
    address public immutable ADDRESS1;
    address public immutable ADDRESS2;

    IonPool public ionPool;

    uint32 public currentIndex;
    uint48 public lastUpdated;

    /**
     * @notice Creates a new `YieldOracle` instance.
     * @param _historicalExchangeRates An intitial set of values for the
     * historical exchange rates matrix.
     * @param _weEth Address of the weETH contract.
     * @param _stader Address of the Stader deposit contract.
     * @param _swell Address of the Swell Eth contract.
     * @param owner Admin address.
     */
    constructor(
        uint64[ILK_COUNT][LOOK_BACK] memory _historicalExchangeRates,
        address _weEth,
        address _stader,
        address _swell,
        address owner
    )
        Ownable(owner)
    {
        for (uint256 i = 0; i < LOOK_BACK;) {
            for (uint256 j = 0; j < ILK_COUNT;) {
                if (_historicalExchangeRates[i][j] == 0) revert InvalidExchangeRate(j);

                historicalExchangeRates[i][j] = _historicalExchangeRates[i][j];

                // forgefmt: disable-next-line
                unchecked { ++j; }
            }

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }

        ADDRESS0 = _weEth;
        ADDRESS1 = _stader;
        ADDRESS2 = _swell;

        _updateAll();
    }

    /**
     * @notice Updates the `IonPool` reference.
     * @param _ionPool pool instance
     */
    function updateIonPool(IonPool _ionPool) external onlyOwner {
        ionPool = _ionPool;
    }

    /**
     * @notice Every update should also accrue interest on `IonPool`. This is
     * because an update to the apy changes interest rates which means the
     * previous interest rate must be accrued, or else its effect will be lost.
     *
     * NOTE: This contract should continue to function as normal even if
     * `IonPool` is paused.
     */
    function updateAll() external {
        if (!ionPool.paused()) ionPool.accrueInterest();
        _updateAll();
    }

    /**
     * @notice Handles the logic for updating the APYs and the historical
     * exchange rates matrix.
     *
     * If the last update was less than `UPDATE_LOCK_LENGTH` seconds ago, then
     * this function will revert.
     *
     * If APY is ever negative, then it will simply be set to 0.
     */
    function _updateAll() internal {
        if (lastUpdated + UPDATE_LOCK_LENGTH > block.timestamp) revert AlreadyUpdated();

        uint256 _currentIndex = currentIndex;
        uint64[ILK_COUNT] storage previousExchangeRates = historicalExchangeRates[_currentIndex];

        for (uint8 i = 0; i < ILK_COUNT;) {
            uint64 newExchangeRate = _getExchangeRate(i);
            uint64 previousExchangeRate = previousExchangeRates[i];

            // Enforce that the exchange rate is not 0
            if (newExchangeRate == 0) revert InvalidExchangeRate(i);

            // If there is a slashing event, the new exchange rate could be
            // lower than the previous exchange rate. In this case, we will set
            // the APY to 0 (and trigger the minimum borrow rate on the
            // protocol). We will not deal with negative APYs here. The
            // potential of a negative APY from a slashing event will last for
            // at most LOOK_BACK days. For that time period, we continue
            // populating the historicalExchangeRates buffer. After LOOK_BACK
            // days, the APY will return to normal.
            uint32 newApy;
            if (newExchangeRate >= previousExchangeRate) {
                uint256 exchangeRateIncrease;

                // Overflow impossible
                unchecked {
                    exchangeRateIncrease = newExchangeRate - previousExchangeRate;
                }

                // It should be noted that if this exchange rate increase were too
                // large, it could overflow the uint32.
                // [WAD] * [APY_PRECISION] / [WAD] = [APY_PRECISION]
                newApy = exchangeRateIncrease.mulDiv(PERIODS, previousExchangeRate).toUint32();
            }

            apys[i] = newApy;

            // Replace previous exchange rates with new exchange rates
            previousExchangeRates[i] = newExchangeRate;

            emit ApyUpdate(i, newApy);

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }

        // update Apy, history with new exchangeRates, and currentIndex
        currentIndex = (currentIndex + 1) % LOOK_BACK;
        // Unsafe cast OK
        lastUpdated = uint48(block.timestamp);
    }

    /**
     * @notice Returns the exchange rate for a given collateral.
     * @param ilkIndex The index of the collateral.
     * @return exchangeRate
     */
    function _getExchangeRate(uint256 ilkIndex) internal view returns (uint64 exchangeRate) {
        if (ilkIndex == 0) {
            IWeEth weEth = IWeEth(ADDRESS0);
            exchangeRate = weEth.getRate().toUint64();
        } else if (ilkIndex == 1) {
            IStaderStakePoolsManager stader = IStaderStakePoolsManager(ADDRESS1);
            exchangeRate = stader.getExchangeRate().toUint64();
        } else if (ilkIndex == 2) {
            ISwEth swell = ISwEth(ADDRESS2);
            exchangeRate = swell.swETHToETHRate().toUint64();
        } else {
            revert InvalidIlkIndex(ilkIndex);
        }
    }
}
