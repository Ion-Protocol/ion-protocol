// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "./IonPool.sol";
import { IWstEth, IStaderStakePoolsManager, ISwEth } from "./interfaces/ProviderInterfaces.sol";
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
 * @dev This contract stores a history of the exchange rates of each collateral
 * for the past `LOOK_BACK` days. Every time, that `updateAll()` is called, it
 * will update the value at `currentIndex` in the `historicalExchangeRates` with the
 * current exchange rate and it will also calculate the APY for each collateral
 * type based on the data currently in the buffer. The APY is calculated by
 * taking the difference between the new element being added and the element
 * being replaced. This provides a growth amount of `LOOK_BACK` days. This value
 * is then projected out to a year.
 */
contract YieldOracle is IYieldOracle, Ownable2Step {
    using Math for uint256;
    using SafeCast for uint256;

    // --- Errors ---

    error InvalidExchangeRate(uint256 ilkIndex);
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

    constructor(
        uint64[ILK_COUNT][LOOK_BACK] memory _historicalExchangeRates,
        address _wstEth,
        address _stader,
        address _swell,
        address owner
    )
        Ownable(owner)
    {
        historicalExchangeRates = _historicalExchangeRates;

        ADDRESS0 = _wstEth;
        ADDRESS1 = _stader;
        ADDRESS2 = _swell;

        _updateAll();
    }

    /**
     * @param _ionPool pool instance
     */
    function updateIonPool(IonPool _ionPool) external onlyOwner {
        ionPool = _ionPool;
    }

    /**
     * @dev Every update should also accrue interest on `IonPool`. This is
     * because an update to the apy changes interest rates which means the
     * previous interest rate must be accrued, or else its effect will be lost.
     */
    function updateAll() external {
        ionPool.accrueInterest();
        _updateAll();
    }

    function _updateAll() internal {
        if (lastUpdated + UPDATE_LOCK_LENGTH > block.timestamp) revert AlreadyUpdated();

        uint256 _currentIndex = currentIndex;
        uint64[ILK_COUNT] storage previousExchangeRates = historicalExchangeRates[_currentIndex];

        for (uint8 i = 0; i < ILK_COUNT;) {
            uint64 newExchangeRate = _getExchangeRate(i);
            uint64 previousExchangeRate = previousExchangeRates[i];

            // Enforce that the exchange rate is not 0 and that it is greater
            // than the previous exchange rate
            if (newExchangeRate == 0 || newExchangeRate < previousExchangeRate) revert InvalidExchangeRate(i);

            uint256 exchangeRateIncrease = newExchangeRate - previousExchangeRate;

            // It should be noted that if this exchange rate increase were too
            // large, it could overflow the uint32.
            // [WAD] * [APY_PRECISION] / [WAD] = [APY_PRECISION]
            uint32 newApy = exchangeRateIncrease.mulDiv(PERIODS, previousExchangeRate).toUint32();
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

    function _getExchangeRate(uint256 ilkIndex) internal view returns (uint64 exchangeRate) {
        if (ilkIndex == 0) {
            IWstEth wstEth = IWstEth(ADDRESS0);
            exchangeRate = wstEth.stEthPerToken().toUint64();
        } else if (ilkIndex == 1) {
            IStaderStakePoolsManager stader = IStaderStakePoolsManager(ADDRESS1);
            exchangeRate = stader.getExchangeRate().toUint64();
        } else {
            ISwEth swell = ISwEth(ADDRESS2);
            exchangeRate = swell.swETHToETHRate().toUint64();
        }
    }
}
