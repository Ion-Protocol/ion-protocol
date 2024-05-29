// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SpotOracle } from "../SpotOracle.sol";
import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";
import { REDSTONE_EZETH_ETH_PRICE_FEED, REDSTONE_DECIMALS } from "../../../Constants.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice The ezETH spot oracle denominated in WETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EzEthWethSpotOracle is SpotOracle {
    using WadRayMath for uint256;
    using SafeCast for int256;

    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE; // seconds

    /**
     * @notice Creates a new `EzEthWethSpotOracle` instance.
     * @param _ltv The loan to value ratio for ezETH <> WETH
     * @param _reserveOracle The associated reserve oracle.
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
     * @notice Gets the price of ezETH in WETH (WETH / ezETH).
     * @dev Redstone oracle returns ETH per ezETH with 8 decimals.
     * @return wEthPerWeEth price of ezETH in WETH. [WAD]
     */
    function getPrice() public view override returns (uint256) {
        // ETH / ezETH [8 decimals]
        (, int256 ethPerEzEth,, uint256 ethPerEzEthUpdatedAt,) = REDSTONE_EZETH_ETH_PRICE_FEED.latestRoundData();
        if (block.timestamp - ethPerEzEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE) {
            return 0; // collateral valuation is zero if oracle data is stale
        } else {
            // (ETH / ezETH)
            return ethPerEzEth.toUint256().scaleUpToWad(REDSTONE_DECIMALS); // [wad]
        }
    }
}
