pragma solidity ^0.8.13;

import { ReserveOracle } from "src/ReserveOracles/ReserveOracle.sol";

/// https://etherscan.io/address/0x60cbe8d88ef519cf3c62414d76f50818d211fea1
interface ChainlinkPoR {
    function getAnswer() external view returns (uint256);
}

contract SwellReserveOracle is ReserveOracle {
    address public protocolFeed;

    constructor(address _token, address _protocolFeed) ReserveOracle(_token) {
        protocolFeed = _protocolFeed;
        exchangeRate = _getProtocolExchangeRate();
        nextExchangeRate = exchangeRate;
    }

    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return ChainlinkPoR(protocolFeed).getAnswer();
    }
}
