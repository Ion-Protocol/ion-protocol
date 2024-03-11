// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SpotOracle } from "../SpotOracle.sol";
import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";
import {
    WSTETH_ADDRESS,
    REDSTONE_RSETH_ETH_PRICE_FEED,
    ETH_PER_STETH_CHAINLINK,
    REDSTONE_DECIMALS
} from "../../../Constants.sol";
import { IWstEth } from "../../../interfaces/ProviderInterfaces.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice The rsETH spot oracle denominated in wstETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract RsEthWstEthSpotOracle is SpotOracle {
    using WadRayMath for uint256;
    using SafeCast for int256;

    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE; // seconds

    /**
     * @notice Creates a new `RsEthWstEthSpotOracle` instance.
     * @param _ltv The loan to value ratio for rsETH <> wstETH
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
     * @notice Gets the price of rsETH in wstETH.
     * (ETH / rsETH) / (ETH / stETH) * (wstETH / stETH) = wstETH / rsETH
     * @dev Redstone oracle returns ETH per rsETH with 8 decimals. This
     * needs to be converted to wstETH per rsETH denomination.
     * @return wstEthPerRsEth price of rsETH in wstETH. [WAD]
     */
    function getPrice() public view override returns (uint256) {
        // ETH / rsETH [8 decimals]
        (, int256 ethPerRsEth,, uint256 ethPerRsEthUpdatedAt,) = REDSTONE_RSETH_ETH_PRICE_FEED.latestRoundData();
        // ETH / stETH [18 decimals]
        (, int256 ethPerStEth,, uint256 ethPerStEthUpdatedAt,) = ETH_PER_STETH_CHAINLINK.latestRoundData();

        if (
            block.timestamp - ethPerRsEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE
                || block.timestamp - ethPerStEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE
        ) {
            return 0; // collateral valuation is zero if oracle data is stale
        } else {
            // (ETH / rsETH) / (ETH / stETH) = stETH / rsETH
            uint256 stEthPerRsEth =
                ethPerRsEth.toUint256().scaleUpToWad(REDSTONE_DECIMALS).wadDivDown(ethPerStEth.toUint256()); // [wad]

            uint256 wstEthPerStEth = IWstEth(WSTETH_ADDRESS).tokensPerStEth(); // [wad]
            return stEthPerRsEth.wadMulDown(wstEthPerStEth); // [wad]
        }
    }
}
