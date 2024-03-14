// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SpotOracle } from "../SpotOracle.sol";
import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";
import {
    WSTETH_ADDRESS,
    REDSTONE_EZETH_ETH_PRICE_FEED,
    ETH_PER_STETH_CHAINLINK,
    REDSTONE_DECIMALS
} from "../../../Constants.sol";
import { IWstEth } from "../../../interfaces/ProviderInterfaces.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice The ezETH spot oracle denominated in wstETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EzEthWstEthSpotOracle is SpotOracle {
    using WadRayMath for uint256;
    using SafeCast for int256;

    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE; // seconds

    /**
     * @notice Creates a new `EzEthWstEthSpotOracle` instance.
     * @param _ltv The loan to value ratio for ezETH <> wstETH
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
     * @notice Gets the price of ezETH in wstETH
     * (ETH / ezETH) / (ETH / stETH) * (wstETH / stETH) = wstETH / ezETH
     */
    function getPrice() public view override returns (uint256) {
        // ETH / ezETH [8 decimals]
        (, int256 ethPerEzEth,, uint256 ethPerEzEthUpdatedAt,) = REDSTONE_EZETH_ETH_PRICE_FEED.latestRoundData();
        // ETH / stETH [18 decimals]
        (, int256 ethPerStEth,, uint256 ethPerStEthUpdatedAt,) = ETH_PER_STETH_CHAINLINK.latestRoundData();

        if (
            block.timestamp - ethPerEzEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE
                || block.timestamp - ethPerStEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE
        ) {
            return 0; // collateral valuation is zero if oracle data is stale
        } else {
            // (ETH / ezETH) / (ETH / ezETH) = stETH / ezETH
            uint256 stEthPerEzEth =
                ethPerEzEth.toUint256().scaleUpToWad(REDSTONE_DECIMALS).wadDivDown(ethPerStEth.toUint256()); // [wad]

            uint256 wstEthPerStEth = IWstEth(WSTETH_ADDRESS).tokensPerStEth(); // [wad]
            // (wstETH / ezETH) = (stETH / ezETH) * (wstETH / stETH)
            return stEthPerEzEth.wadMulDown(wstEthPerStEth); // [wad]
        }
    }
}
