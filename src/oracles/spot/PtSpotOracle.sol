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

    /**
     * @notice Construct a new `PtSpotOracle` instance
     * @param _market The Pendle Market to get the PT price from
     * @param _twapDuration The duration of the TWAP
     * @param _ltv The Loan To Value ratio
     * @param _reserveOracle The oracle to get the reserve price from
     */
    constructor(
        IPMarketV3 _market,
        uint32 _twapDuration,
        uint256 _ltv,
        address _reserveOracle
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        (,,,,, uint16 observationCardinalityNext) = _market._storage();

        uint256 minimumOracleSlots = _twapDuration / 12;

        if (observationCardinalityNext < minimumOracleSlots) revert InsufficientOracleSlots(observationCardinalityNext);

        market = _market;
        twapDuration = _twapDuration;
    }

    /**
     * @inheritdoc SpotOracle
     */
    function getPrice() public view override returns (uint256 price) {
        if (market.expiry() <= block.timestamp) return 0;

        return market.getPtToSyRate(twapDuration);
    }
}
