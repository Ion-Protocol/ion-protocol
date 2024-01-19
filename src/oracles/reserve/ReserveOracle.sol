// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IReserveFeed } from "src/interfaces/IReserveFeed.sol";
import { WadRayMath, RAY } from "src/libraries/math/WadRayMath.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

// should equal to the number of feeds available in the contract
uint8 constant FEED_COUNT = 3;
uint256 constant UPDATE_COOLDOWN = 1 hours;

abstract contract ReserveOracle {
    using WadRayMath for uint256;

    uint8 public immutable ILK_INDEX;
    uint8 public immutable QUORUM; // the number of feeds to aggregate
    uint256 public immutable MAX_CHANGE; // maximum change allowed in percentage [ray] i.e. 3e25 [ray] would be 3%

    IReserveFeed public immutable FEED0; // different reserve oracle feeds excluding the protocol exchange rate
    IReserveFeed public immutable FEED1;
    IReserveFeed public immutable FEED2;

    uint256 public currentExchangeRate; // [wad] the bounded queried last time
    uint256 public lastUpdated; // [wad] the bounded queried last time

    // --- Events ---
    event UpdateExchangeRate(uint256 exchangeRate);

    // --- Errors ---
    error InvalidQuorum(uint8 invalidQuorum);
    error InvalidFeedLength(uint256 invalidLength);
    error InvalidMaxChange(uint256 invalidMaxChange);
    error InvalidMinMax(uint256 invalidMin, uint256 invalidMax);
    error InvalidInitialization(uint256 invalidExchangeRate);
    error UpdateCooldown(uint256 lastUpdated);

    constructor(uint8 _ilkIndex, address[] memory _feeds, uint8 _quorum, uint256 _maxChange) {
        if (_feeds.length != FEED_COUNT) revert InvalidFeedLength(_feeds.length);
        if (_quorum > FEED_COUNT) revert InvalidQuorum(_quorum);
        if (_maxChange == 0 || _maxChange > RAY) revert InvalidMaxChange(_maxChange);

        ILK_INDEX = _ilkIndex;
        QUORUM = _quorum;
        MAX_CHANGE = _maxChange;

        FEED0 = IReserveFeed(_feeds[0]);
        FEED1 = IReserveFeed(_feeds[1]);
        FEED2 = IReserveFeed(_feeds[2]);
    }

    // --- Override ---
    function _getProtocolExchangeRate() internal view virtual returns (uint256);

    function getProtocolExchangeRate() external view returns (uint256) {
        return _getProtocolExchangeRate();
    }

    /**
     * @dev queries values from whitelisted data feeds and calculates
     *      the min. Does not include the protocol exchange rate.
     * @notice if quorum isn't met, should revert
     */
    function _aggregate(uint8 _ILK_INDEX) internal view returns (uint256 val) {
        if (QUORUM == 0) {
            return type(uint256).max;
        } else if (QUORUM == 1) {
            val = FEED0.getExchangeRate(_ILK_INDEX);
        } else if (QUORUM == 2) {
            uint256 feed0ExchangeRate = FEED0.getExchangeRate(_ILK_INDEX);
            uint256 feed1ExchangeRate = FEED1.getExchangeRate(_ILK_INDEX);
            val = ((feed0ExchangeRate + feed1ExchangeRate) / uint256(QUORUM));
        } else if (QUORUM == 3) {
            uint256 feed0ExchangeRate = FEED0.getExchangeRate(_ILK_INDEX);
            uint256 feed1ExchangeRate = FEED1.getExchangeRate(_ILK_INDEX);
            uint256 feed2ExchangeRate = FEED2.getExchangeRate(_ILK_INDEX);
            val = ((feed0ExchangeRate + feed1ExchangeRate + feed2ExchangeRate) / uint256(QUORUM));
        }
    }

    // bound the final reported value between the min and the max
    function _bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min > max) revert InvalidMinMax(min, max);

        return Math.max(min, Math.min(max, value));
    }

    function _initializeExchangeRate() internal {
        currentExchangeRate = Math.min(_getProtocolExchangeRate(), _aggregate(ILK_INDEX));
        if (currentExchangeRate == 0) {
            revert InvalidInitialization(currentExchangeRate);
        }

        emit UpdateExchangeRate(currentExchangeRate);
    }

    // @dev Takes the minimum between the aggregated values and the protocol exchange rate,
    // then bounds it up to the maximum change and writes the bounded value to the state.
    // NOTE: keepers should call this update to reflect recent values

    function updateExchangeRate() external {
        if (block.timestamp - lastUpdated < UPDATE_COOLDOWN) revert UpdateCooldown(lastUpdated);

        uint256 _currentExchangeRate = currentExchangeRate;

        uint256 minimum = Math.min(_getProtocolExchangeRate(), _aggregate(ILK_INDEX));
        uint256 diff = _currentExchangeRate.rayMulDown(MAX_CHANGE);

        uint256 bounded = _bound(minimum, _currentExchangeRate - diff, _currentExchangeRate + diff);
        currentExchangeRate = bounded;

        lastUpdated = block.timestamp;

        emit UpdateExchangeRate(bounded);
    }
}
