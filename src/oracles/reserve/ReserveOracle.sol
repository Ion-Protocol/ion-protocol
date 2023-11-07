// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IReserveFeed } from "src/interfaces/IReserveFeed.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";

import { console2 } from "forge-std/console2.sol";

// should equal to the number of feeds available in the contract
uint8 constant MAX_FEED_COUNT = 3;

abstract contract ReserveOracle is Ownable {
    using SafeCast for *;
    using RoundedMath for uint256;

    uint8 public immutable ilkIndex;

    uint8 public immutable quorum; // the number of feeds to aggregate

    uint256 public immutable maxChange; // maximum change allowed in percentage [ray] i.e. 3e25 [ray] would be 3%

    uint256 public currentExchangeRate; // the bounded queried last time

    IReserveFeed public immutable feed0; // different reserve oracle feeds excluding the protocol exchange rate
    IReserveFeed public immutable feed1;
    IReserveFeed public immutable feed2;

    // --- Events ---
    event UpdateExchangeRate(uint256 exchangeRate);

    // --- Errors ---
    error InvalidQuorum(uint8 quorum);
    error InvalidFeedLength(uint256 length);
    error InvalidInitialization(uint256 exchangeRate);

    // --- Override ---
    function _getProtocolExchangeRate() internal view virtual returns (uint256);

    function getProtocolExchangeRate() external view returns (uint256) {
        return _getProtocolExchangeRate();
    }

    constructor(uint8 _ilkIndex, address[] memory _feeds, uint8 _quorum, uint256 _maxChange) Ownable(msg.sender) {
        if (_feeds.length > MAX_FEED_COUNT) {
            revert InvalidFeedLength(_feeds.length);
        }
        if (_quorum > MAX_FEED_COUNT) {
            revert InvalidQuorum(_quorum);
        }

        ilkIndex = _ilkIndex;
        quorum = _quorum;
        maxChange = _maxChange;

        feed0 = IReserveFeed(_feeds[0]);
        feed1 = IReserveFeed(_feeds[1]);
        feed2 = IReserveFeed(_feeds[2]);
    }

    /**
     * @dev queries values from whitelisted data feeds and calculates
     * the min. Does not include the protocol exchange rate.
     * @notice if quorum isn't met, should revert
     */
    function _aggregate(uint8 _ilkIndex) internal view returns (uint256 val) {
        if (quorum == 0) {
            return type(uint256).max;
        } else if (quorum == 1) {
            val = IReserveFeed(feed0).getExchangeRate(_ilkIndex);
        } else if (quorum == 2) {
            uint256 feed0ExchangeRate = IReserveFeed(feed0).getExchangeRate(_ilkIndex);
            uint256 feed1ExchangeRate = IReserveFeed(feed1).getExchangeRate(_ilkIndex);
            val = ((feed0ExchangeRate + feed1ExchangeRate) / uint256(quorum));
        } else if (quorum == 3) {
            uint256 feed0ExchangeRate = IReserveFeed(feed0).getExchangeRate(_ilkIndex);
            uint256 feed1ExchangeRate = IReserveFeed(feed1).getExchangeRate(_ilkIndex);
            uint256 feed2ExchangeRate = IReserveFeed(feed2).getExchangeRate(_ilkIndex);

            val = ((feed0ExchangeRate + feed1ExchangeRate + feed2ExchangeRate) / uint256(quorum));
        }
    }

    // bound the final reported value between the min and the max
    function _bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        return Math.max(min, Math.min(max, value));
    }

    // TODO: Why public?
    function initializeExchangeRate() public {
        currentExchangeRate = Math.min(_getProtocolExchangeRate(), _aggregate(ilkIndex));
        if (currentExchangeRate == 0) {
            revert InvalidInitialization(currentExchangeRate);
        }
    }

    // @dev Takes the minimum between the aggregated values and the protocol exchange rate,
    //      then bounds it up to the maximum change and writes the bounded value to the state.
    // NOTE: keepers should call this update to reflect recent values
    function updateExchangeRate() public {
        uint256 _currentExchangeRate = currentExchangeRate;

        uint256 minimum = Math.min(_getProtocolExchangeRate(), _aggregate(ilkIndex));
        uint256 diff = _currentExchangeRate.rayMulDown(maxChange);

        uint256 bounded = _bound(minimum, _currentExchangeRate - diff, _currentExchangeRate + diff);
        currentExchangeRate = bounded;

        emit UpdateExchangeRate(bounded);
    }
}
