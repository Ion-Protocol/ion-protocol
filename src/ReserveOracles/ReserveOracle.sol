pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IReserveFeed} from "src/interfaces/IReserveFeed.sol";

abstract contract ReserveOracle is Ownable {
    uint256 public exchangeRate; // final value to be reported

    uint256 public nextExchangeRate; // final value to be reported next

    uint256 public interval; // Unix time stamp in s

    uint256 public prev; // last updated Unix time stamp in s

    uint256 public quorum; // total number of inputs to aggregate

    address public immutable token; // address of the collateral token

    address[] public feeds; // reserve data feeds

    // --- Events ---
    event UpdateTokens(bytes32 indexed name, address indexed addr);
    event UpdateInterval(uint256 indexed interval);
    event UpdateFeed(uint256 indexed exchangeRate, uint256 indexed nextExchangeRate);
    event RemoveFeed(address indexed addr);

    // --- Administrative ---
    function updateInterval(uint256 _interval) external onlyOwner {
        interval = _interval;
        emit UpdateInterval(_interval);
    }

    function addFeed(address _addr) external onlyOwner {
        feeds.push(_addr);
    }

    function removeFeed(address _addr) external onlyOwner {
        for (uint256 i = 0; i < feeds.length;) {
            if (feeds[i] == _addr) {
                address toDelete = feeds[i];
                feeds[i] = feeds[feeds.length - 1];
                feeds[feeds.length - 1] = toDelete;
                feeds.pop();
                emit RemoveFeed(_addr);
            }
            unchecked {
                ++i; 
            }
        }
    }

    // --- Info ---
    function feedCount() external view returns (uint256) {
        return feeds.length;
    }

    // --- Helpers ---
    function _checkInterval() public view returns (bool) {
        return block.timestamp >= prev + interval;
    }

    function _min(uint256 x, uint256 y) public pure returns (uint256) {
        return x < y ? x : y;
    }

    // --- Override ---
    function _getProtocolExchangeRate() internal virtual returns (uint256) {}
    function getProtocolExchangeRate() external virtual returns (uint256) {
        return _getProtocolExchangeRate(); 
    }

    constructor(address _token) {
        token = _token;
    }

    /**
     * @dev queries values from whitelisted data feeds and calculates
     * the median.
     * @notice if quorum isn't met, should revert.
     */
    function _aggregate() internal view returns (uint256 val) {
        uint256 len = feeds.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 res = IReserveFeed(feeds[i]).reserves(token);
            val += res;
        }
        val = val / len;
    }

    /**
     * @dev Updates
     * If the designated interval hasn't passed yet,
     * @notice Any incentivized party can call this function to update the value
     * that this contract will return upon a query.
     */
    function updateFeed() external {
        require(_checkInterval(), "ReserveFeed/interval-not-passed");
        uint256 aggregateRate = _aggregate();
        uint256 protocolRate = _getProtocolExchangeRate();
        exchangeRate = nextExchangeRate;
        nextExchangeRate = _min(aggregateRate, protocolRate);

        emit UpdateFeed(exchangeRate, nextExchangeRate);
    }
}