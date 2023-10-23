// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IReserveFeed } from "src/interfaces/IReserveFeed.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "forge-std/console.sol"; 

// overridden by a collateral-specific ReserveOracle contract
uint8 constant FEED_COUNT = 3;  

abstract contract ReserveOracle is Ownable {
    using SafeCast for *; 

    // --- Errors --- 
    error InvalidQuorum(uint8 quorum); 
    error InvalidFeedLength(uint8 length); 
    
    uint72 public exchangeRate; // final value to be reported

    uint72 public nextExchangeRate; // final value to be reported next

    uint8 public immutable ilkIndex;

    uint8 public immutable quorum; // the number of feeds to aggregate
    
    uint256 public immutable interval; // Unix time stamp in s

    uint256 public immutable prev; // last updated Unix time stamp in s

    IReserveFeed public immutable feed0; // different reserve oracle feeds excluding the protocol exchange rate 
    IReserveFeed public immutable feed1; 
    IReserveFeed public immutable feed2; 

    // --- Events ---

    event UpdateFeed(uint72 exchangeRate, uint72 nextExchangeRate);

    // --- Helpers ---

    function _min(uint72 x, uint72 y) public pure returns (uint72) {
        return x < y ? x : y;
    }

    // --- Override ---
    function _getProtocolExchangeRate() internal view virtual returns (uint72) { }

    function getProtocolExchangeRate() external view returns (uint72) {
        return _getProtocolExchangeRate();
    }

    constructor(uint8 _ilkIndex, address[] memory _feeds, uint8 _quorum) Ownable(msg.sender) {
        if (_feeds.length > FEED_COUNT) {
            revert InvalidFeedLength(_feeds.length.toUint8()); 
        }
        if (_quorum > FEED_COUNT) {
            revert InvalidQuorum(_quorum); 
        }

        ilkIndex = _ilkIndex; 
        quorum = _quorum; 
        
        feed0 = IReserveFeed(_feeds[0]);
        feed1 = IReserveFeed(_feeds[1]); 
        feed2 = IReserveFeed(_feeds[2]); 
    }

    /**
     * @dev queries values from whitelisted data feeds and calculates
     * the min. Does not include the protocol exchange rate. 
     * @notice if quorum isn't met, should revert
     */
    function _aggregate(uint8 _ilkIndex) internal view returns (uint72 val) {
        if (quorum == 0) {
            return type(uint72).max; 
        }
        else if (quorum == 1) {
            uint256 feed0ExchangeRate = IReserveFeed(feed0).getExchangeRate(_ilkIndex); 
            return feed0ExchangeRate.toUint72(); 
        } 
        else if (quorum == 2) {
            uint256 feed0ExchangeRate = IReserveFeed(feed0).getExchangeRate(_ilkIndex); 
            uint256 feed1ExchangeRate = IReserveFeed(feed1).getExchangeRate(_ilkIndex); 
            val = ((feed0ExchangeRate + feed1ExchangeRate) / uint256(quorum)).toUint72(); 
            return val.toUint72(); 
        } else if (quorum == 3) { 
            console.log("in quorum 3"); 
            uint256 feed0ExchangeRate = IReserveFeed(feed0).getExchangeRate(_ilkIndex); 
            uint256 feed1ExchangeRate = IReserveFeed(feed1).getExchangeRate(_ilkIndex); 
            uint256 feed2ExchangeRate = IReserveFeed(feed2).getExchangeRate(_ilkIndex);
            val = ((feed0ExchangeRate + feed1ExchangeRate + feed2ExchangeRate) / uint256(quorum)).toUint72();
            console.log("val: ", val); 
            return val.toUint72(); 
        }
    }

    // @dev Mnimizes the difference 
    function getExchangeRate() external view returns (uint72) {      
        return _min(_getProtocolExchangeRate(), _aggregate(ilkIndex)); 
    }
}
