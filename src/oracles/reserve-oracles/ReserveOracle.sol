// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IReserveFeed } from "src/interfaces/IReserveFeed.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

uint32 constant ILK_COUNT = 8;

abstract contract ReserveOracle is Ownable {
    using SafeCast for *; 
    
    uint72 public exchangeRate; // final value to be reported

    uint72 public nextExchangeRate; // final value to be reported next

    uint256 public immutable quorum; // total number of inputs to aggregate
    
    uint256 public immutable interval; // Unix time stamp in s

    uint256 public immutable prev; // last updated Unix time stamp in s

    address public immutable token; // address of the collateral token

    // TODO: should be made immutable 
    address[ILK_COUNT] public feeds; // reserve data feeds

    // --- Events ---

    event UpdateFeed(uint72 exchangeRate, uint72 nextExchangeRate);

    // --- Helpers ---
    function _checkInterval() public view returns (bool) {
        return block.timestamp >= prev + interval;
    }

    function _min(uint72 x, uint72 y) public pure returns (uint72) {
        return x < y ? x : y;
    }

    // --- Override ---
    function _getProtocolExchangeRate() internal virtual returns (uint256) { }

    function getProtocolExchangeRate() external returns (uint256) {
        return _getProtocolExchangeRate();
    }

    constructor(address _token, address[ILK_COUNT] memory _feeds) Ownable(msg.sender) {
        token = _token;
        feeds = _feeds; 
    }

    /**
     * @dev queries values from whitelisted data feeds and calculates
     * the min.
     * @notice if quorum isn't met, should revert
     */
    function _aggregate() internal view returns (uint72) {
        uint256 len = feeds.length;
        uint256 val; 
        for (uint32 i = 0; i < len; i++) {
            uint256 res = IReserveFeed(feeds[i]).reserves(token);
            val += res;
        }
        // TODO: if quorum isn't met, should revert 
        val = (val / len).toUint72();
    }

    /**
     * @dev Updates
     * If the designated interval hasn't passed yet,
     * @notice Any incentivized party can call this function to update the value
     * that this contract will return upon a query.
     */
    function updateFeed() external {
        require(_checkInterval(), "ReserveFeed/interval-not-passed");
        uint72 aggregateRate = _aggregate().toUint72();
        uint72 protocolRate = _getProtocolExchangeRate().toUint72();
        exchangeRate = nextExchangeRate;
        nextExchangeRate = _min(aggregateRate, protocolRate);

        emit UpdateFeed(exchangeRate, nextExchangeRate);
    }
}
