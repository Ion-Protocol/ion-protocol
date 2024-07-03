// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SpotOracle } from "../../../oracles/spot/SpotOracle.sol";
import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";
import { BASE_WEETH_ETH_PRICE_CHAINLINK, BASE_SEQUENCER_UPTIME_FEED } from "../../../Constants.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice The weETH spot oracle denominated in WETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract WeEthWethSpotOracle is SpotOracle {
    using WadRayMath for uint256;
    using SafeCast for int256;

    error SequencerDown();
    error GracePeriodNotOver();

    /**
     * @notice The maximum delay for the oracle update in seconds before the
     * data is considered stale. 
     */
    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE; // seconds

    /**
     * @notice Amount of time to wait after the sequencer restarts.
     */
    uint256 public immutable GRACE_PERIOD; 

    /**
     * @notice Creates a new `WeEthWethSpotOracle` instance.
     * @param _ltv The loan to value ratio for the weETH/WETH market.
     * @param _reserveOracle The associated reserve oracle.
     * @param _maxTimeFromLastUpdate The maximum delay for the oracle update in seconds
     */
    constructor(
        uint256 _ltv,
        address _reserveOracle,
        uint256 _maxTimeFromLastUpdate,
        uint256 _gracePeriod
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        MAX_TIME_FROM_LAST_UPDATE = _maxTimeFromLastUpdate;
        GRACE_PERIOD = _gracePeriod;
    }

    /**
     * @notice Gets the price of weETH in WETH.
     * @dev Redstone oracle returns ETH per weETH with 8 decimals. This
     * @return wethPerWeEth price of weETH in WETH. [WAD]
     */
    function getPrice() public view override returns (uint256) {
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

        (
            /*uint80 roundID*/
            ,
            int256 ethPerWeEth,
            /*uint startedAt*/
            ,
            uint256 ethPerWeEthUpdatedAt,
            /*uint80 answeredInRound*/
        ) = BASE_WEETH_ETH_PRICE_CHAINLINK.latestRoundData(); // [WAD]

        if (block.timestamp - ethPerWeEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE) {
            return 0; // collateral valuation is zero if oracle data is stale
        } else {
            return ethPerWeEth.toUint256(); // [wad]
        }
    }
}
