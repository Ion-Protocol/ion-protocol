// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IStaderStakePoolsManager } from "../../../interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "../ReserveOracle.sol";

/**
 * @notice Reserve oracle for ETHx.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EthXReserveOracle is ReserveOracle {
    address public immutable PROTOCOL_FEED;

    /**
     * @notice Creates a new `EthXReserveOracle` instance.
     * @param _protocolFeed Data source for the LST provider exchange rate.
     * @param _ilkIndex of ETHx.
     * @param _feeds List of alternative data sources for the ETHx exchange rate.
     * @param _quorum The amount of alternative data sources to aggregate.
     * @param _maxChange Maximum percent change between exchange rate updates. [RAY]
     */
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

    /**
     * @notice Returns the exchange rate between ETH and ETHx.
     * @return Exchange rate between ETH and ETHx.
     */
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return IStaderStakePoolsManager(PROTOCOL_FEED).getExchangeRate();
    }
}
