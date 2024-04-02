// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SpotOracle } from "./SpotOracle.sol";

import { PendleMarketV3 } from "pendle-core-v2-public/core/Market/v3/PendleMarketV3.sol";
import { PendlePtOracleLib } from "pendle-core-v2-public/oracles/PendlePtOracleLib.sol";

/**
 * @notice
 *
 * @dev This contract assumes that the SY is pegged 1:1 with the underlying
 * asset of IonPool.
 */
contract PtSpotOracle is SpotOracle {
    using PendlePtOracleLib for PendleMarketV3;

    error InsufficientOracleSlots(uint256 currentSlots);

    PendleMarketV3 public immutable market;
    uint32 public immutable twapDuration;

    constructor(
        PendleMarketV3 _market,
        uint32 _twapDuration,
        uint256 _ltv,
        address _reserveOracle
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        market = _market;

        (,,,,, uint16 observationCardinalityNext) = market._storage();

        twapDuration = _twapDuration;

        uint256 minimumOracleSlots = twapDuration / 12;

        if (observationCardinalityNext < minimumOracleSlots) revert InsufficientOracleSlots(observationCardinalityNext);
    }

    function getPrice() public view override returns (uint256 price) {
        return market.getPtToSyRate(twapDuration);
    }
}
