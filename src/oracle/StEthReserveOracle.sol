pragma solidity ^0.8.13;

import { ReserveOracle } from "./ReserveOracle.sol";

interface wstEth {
    function exchangeRate() external view returns (uint256);
}

contract StEthReserveOracle is ReserveOracle {
    address public protocolFeed;

    constructor(address _token, address _protocolFeed) ReserveOracle(_token) {
        protocolFeed = _protocolFeed;
        exchangeRate = _getProtocolExchangeRate();
        nextExchangeRate = exchangeRate;
    }

    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return wstEth(protocolFeed).exchangeRate();
    }
}
