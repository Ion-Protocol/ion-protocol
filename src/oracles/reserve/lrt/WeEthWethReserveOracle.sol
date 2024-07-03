// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ReserveOracle } from "../ReserveOracle.sol";
import { BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK, BASE_SEQUENCER_UPTIME_FEED } from "../../../Constants.sol";
import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice Reserve oracle for weETH.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract WeEthWethReserveOracle is ReserveOracle {
    using WadRayMath for uint256;
    using SafeCast for int256;

    error SequencerDown();
    error GracePeriodNotOver();
    error MaxTimeFromLastUpdateExceeded(uint256, uint256);

    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE; // seconds
    uint256 public immutable GRACE_PERIOD;

    /**
     * @notice Creates a new `WeEthWethReserveOracle` instance. Provides
     * the amount of WETH equal to one weETH.
     * ETH / eETH is 1 since eETH is rebasing. Depeg here would reflect in eETH / wETH
     * exchange rate.
     * @dev The value of weETH denominated in WETH by the provider.
     * @param _ilkIndex of weETH.
     * @param _feeds List of alternative data sources for the weETH exchange rate.
     * @param _quorum The amount of alternative data sources to aggregate.
     * @param _maxChange Maximum percent change between exchange rate updates. [RAY]
     */
    constructor(
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum,
        uint256 _maxChange,
        uint256 _maxTimeFromLastUpdate,
        uint256 _gracePeriod
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum, _maxChange)
    {
        MAX_TIME_FROM_LAST_UPDATE = _maxTimeFromLastUpdate;
        GRACE_PERIOD = _gracePeriod;
        _initializeExchangeRate();
    }

    /**
     * @notice Returns the exchange rate between WETH and weETH.
     * @return Exchange rate between WETH and weETH.
     */
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        (
            /*uint80 roundID*/
            ,
            int256 answer,
            uint256 startedAt,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = BASE_SEQUENCER_UPTIME_FEED.latestRoundData();

        if (answer == 1) revert SequencerDown();
        if (block.timestamp - startedAt <= GRACE_PERIOD) revert GracePeriodNotOver();

        (, int256 ethPerWeEth,, uint256 ethPerWeEthUpdatedAt,) =
            BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK.latestRoundData();

        if (block.timestamp - ethPerWeEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE) {
            revert MaxTimeFromLastUpdateExceeded(block.timestamp, ethPerWeEthUpdatedAt);
        } else {
            return ethPerWeEth.toUint256(); // [WAD]
        }
    }
}
