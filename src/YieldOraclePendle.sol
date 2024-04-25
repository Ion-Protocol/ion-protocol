// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IYieldOracle } from "./interfaces/IYieldOracle.sol";
import { WadRayMath } from "./libraries/math/WadRayMath.sol";

import { IPMarketV3 } from "pendle-core-v2-public/interfaces/IPMarketV3.sol";
import { LogExpMath } from "pendle-core-v2-public/core/libraries/math/LogExpMath.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

using SafeCast for uint256;
using SafeCast for int256;
using WadRayMath for uint256;

/**
 * @notice Yield Oracle for Pendle Markets
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract YieldOraclePendle is IYieldOracle {
    error InsufficientOracleSlots(uint256 currentSlots);

    IPMarketV3 public immutable market;
    uint32 public immutable twapDuration;

    uint256 public immutable yieldCeiling;

    /**
     * @notice Construct a new `YieldOraclePendle` instance
     * @param _market The Pendle Market to get the APY from
     * @param _twapDuration The duration of the TWAP
     * @param _yieldCeiling The maximum APY
     */
    constructor(IPMarketV3 _market, uint32 _twapDuration, uint256 _yieldCeiling) {
        (,,,,, uint16 observationCardinalityNext) = _market._storage();

        uint256 minimumOracleSlots = twapDuration / 12;

        if (observationCardinalityNext < minimumOracleSlots) revert InsufficientOracleSlots(observationCardinalityNext);

        market = _market;
        twapDuration = _twapDuration;
        yieldCeiling = _yieldCeiling;
    }

    /**
     * @notice Get the APY for a given collateral
     */
    function apys(uint256) external view override returns (uint32) {
        uint256 expiry = market.expiry();

        if (expiry <= block.timestamp) return 0;

        uint32[] memory durations = new uint32[](2);
        durations[0] = twapDuration;

        uint216[] memory lnImpliedRateCumulative = market.observe(durations);
        uint256 lnImpliedRate = ((lnImpliedRateCumulative[1] - lnImpliedRateCumulative[0]) / twapDuration);

        // For a 40% APY, implied rate will be 1.4e18
        uint256 impliedRate = LogExpMath.exp(lnImpliedRate.toInt256()).toUint256();
        impliedRate -= 1e18;

        uint256 _yieldCeiling = yieldCeiling;
        if (impliedRate > _yieldCeiling) impliedRate = _yieldCeiling;

        return impliedRate.scaleDown({ from: 18, to: 8 }).toUint32();
    }
}
