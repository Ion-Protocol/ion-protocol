// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SpotOracle } from "./SpotOracle.sol";

import { IPMarketV3 } from "pendle-core-v2-public/interfaces/IPMarketV3.sol";
import { PendlePtOracleLib } from "pendle-core-v2-public/oracles/PendlePtOracleLib.sol";

/**
 * @notice Spot Oracle for PT markets
 *
 * @dev This contract assumes that the SY is pegged 1:1 with the underlying
 * asset of IonPool.
 *
 * This is a major assumption to be aware of since this oracle will return a
 * valuation in SY, which may or may not be the same as the underlying in the
 * IonPool.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract PtSpotOracle is SpotOracle {
    using PendlePtOracleLib for IPMarketV3;

    error InsufficientOracleSlots(uint256 currentSlots);

    IPMarketV3 public immutable market;
    uint32 public immutable twapDuration;

    constructor(
        IPMarketV3 _market,
        uint32 _twapDuration,
        uint256 _ltv,
        address _reserveOracle
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        (,,,,, uint16 observationCardinalityNext) = _market._storage();

        uint256 minimumOracleSlots = twapDuration / 12;

        if (observationCardinalityNext < minimumOracleSlots) revert InsufficientOracleSlots(observationCardinalityNext);

        market = _market;
        twapDuration = _twapDuration;
    }

    function getPrice() public view override returns (uint256 price) {
        return market.getPtToSyRate(twapDuration);
    }
}
