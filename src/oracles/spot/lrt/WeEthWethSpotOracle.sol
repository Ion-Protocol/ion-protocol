// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SpotOracle } from "../../../oracles/spot/SpotOracle.sol";
import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";
import { BASE_WEETH_ETH_PRICE_CHAINLINK } from "../../../Constants.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice The weETH spot oracle denominated in WETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract WeEthWethSpotOracle is SpotOracle {
    using WadRayMath for uint256;
    using SafeCast for int256;

    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE; // seconds

    /**
     * @notice Creates a new `WeEthWethSpotOracle` instance.
     * @param _ltv The loan to value ratio for the weETH/WETH market.
     * @param _reserveOracle The associated reserve oracle.
     * @param _maxTimeFromLastUpdate The maximum delay for the oracle update in seconds
     */
    constructor(
        uint256 _ltv,
        address _reserveOracle,
        uint256 _maxTimeFromLastUpdate
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        MAX_TIME_FROM_LAST_UPDATE = _maxTimeFromLastUpdate;
    }

    /**
     * @notice Gets the price of weETH in WETH.
     * @dev Redstone oracle returns ETH per weETH with 8 decimals. This
     * @return wethPerWeEth price of weETH in WETH. [WAD]
     */
    function getPrice() public view override returns (uint256) {
        (, int256 ethPerWeEth,, uint256 ethPerWeEthUpdatedAt,) = BASE_WEETH_ETH_PRICE_CHAINLINK.latestRoundData(); // [WAD]
        if (block.timestamp - ethPerWeEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE) {
            return 0; // collateral valuation is zero if oracle data is stale
        } else {
            return ethPerWeEth.toUint256(); // [wad]
        }
    }
}
