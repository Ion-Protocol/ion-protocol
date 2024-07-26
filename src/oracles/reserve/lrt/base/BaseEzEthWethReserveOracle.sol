// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WadRayMath } from "../../../../libraries/math/WadRayMath.sol";
import { ReserveOracle } from "../../ReserveOracle.sol";
import { BASE_EZETH_ETH_EXCHANGE_RATE_CHAINLINK, BASE_SEQUENCER_UPTIME_FEED } from "../../../../Constants.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

/**
 * @notice Reserve Oracle for ezETH denominated in WETH.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract BaseEzEthWethReserveOracle is ReserveOracle {
    using WadRayMath for uint256;
    using SafeCast for int256;

    error SequencerDown();
    error GracePeriodNotOver();
    error MaxTimeFromLastUpdateExceeded(uint256, uint256);

    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE; // seconds
    uint256 public immutable GRACE_PERIOD;

    /**
     * @notice Creates a new `BaseEzEthWethReserveOracle` instance. Provides
     * the amount of WETH equal to one ezETH (ETH / ezETH).
     * @dev The value of ezETH denominated in WETH by Chainlink.
     * @param _feeds List of alternative data sources for the WETH/ezETH exchange rate.
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

        (, int256 ethPerEzEth,, uint256 ethPerEzEthUpdatedAt,) =
            BASE_EZETH_ETH_EXCHANGE_RATE_CHAINLINK.latestRoundData();

        if (block.timestamp - ethPerEzEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE) {
            revert MaxTimeFromLastUpdateExceeded(block.timestamp - ethPerEzEthUpdatedAt, MAX_TIME_FROM_LAST_UPDATE);
        } else {
            return ethPerEzEth.toUint256();
        }
    }
}
