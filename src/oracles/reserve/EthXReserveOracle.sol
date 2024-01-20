// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IStaderStakePoolsManager } from "../../interfaces/ProviderInterfaces.sol";
import { WadRayMath } from "../../libraries/math/WadRayMath.sol";
import { ReserveOracle } from "./ReserveOracle.sol";

contract EthXReserveOracle is ReserveOracle {
    address public immutable PROTOCOL_FEED;

    // @param _quorum number of extra feeds to aggregate. If any of the feeds fail, pause the protocol.
    constructor(
        address _protocolFeed,
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum,
        uint256 _maxChange
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum, _maxChange)
    {
        PROTOCOL_FEED = _protocolFeed;
        _initializeExchangeRate();
    }

    // @dev exchange rate is total LST supply divided by total underlying ETH
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return IStaderStakePoolsManager(PROTOCOL_FEED).getExchangeRate();
    }
}
