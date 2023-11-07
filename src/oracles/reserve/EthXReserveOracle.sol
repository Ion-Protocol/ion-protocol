// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IStaderStakePoolsManager } from "src/interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "./ReserveOracle.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";

uint8 constant ethXDecimals = 18;

contract EthXReserveOracle is ReserveOracle {
    using WadRayMath for uint256;

    address public protocolFeed;

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
        protocolFeed = _protocolFeed;
        initializeExchangeRate();
    }

    // @dev exchange rate is total LST supply divided by total underlying ETH
    // NOTE:
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return IStaderStakePoolsManager(protocolFeed).getExchangeRate();
    }
}
