// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SpotOracle } from "../../oracles/spot/SpotOracle.sol";
import { WadRayMath } from "../../libraries/math/WadRayMath.sol";
import { WSTETH_ADDRESS, REDSTONE_WEETH_ETH_PRICE_FEED, ETH_PER_STETH_CHAINLINK } from "../../Constants.sol";
import { IWstEth } from "../../interfaces/ProviderInterfaces.sol";
import { IChainlink } from "../../interfaces/IChainlink.sol";
import { IRedstonePriceFeed } from "../../interfaces/IRedstone.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

uint8 constant REDSTONE_DECIMALS = 8;

/**
 * @notice The weETH spot oracle denominated in wstETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract WeEthWstEthSpotOracle is SpotOracle {
    using WadRayMath for uint256;
    using SafeCast for int256;

    uint256 maxTimeFromLastUpdate; // seconds

    /**
     * @notice Creates a new `WeEthWstEthSpotOracle` instance.
     * @param _ltv The loan to value ratio for weETH <> wstETH
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
        maxTimeFromLastUpdate = _maxTimeFromLastUpdate;
    }

    /**
     * @notice Gets the price of weETH in wstETH.
     * (ETH / weETH) / (ETH / stETH) * (wstETH / stETH) = wstETH / weETH
     * @dev Redstone oracle returns ETH per weETH with 8 decimals. This
     * needs to be converted to wstETH per weETH denomination.
     * @return wstEthPerWeEth price of weETH in wstETH. [WAD]
     */
    function getPrice() public view override returns (uint256) {
        (, int256 ethPerWeEth,, uint256 ethPerWeEthUpdatedAt,) =
            IRedstonePriceFeed(REDSTONE_WEETH_ETH_PRICE_FEED).latestRoundData(); // ETH
            // / weETH [8 decimals]
        (, int256 ethPerStEth,, uint256 ethPerStEthUpdatedAt,) = IChainlink(ETH_PER_STETH_CHAINLINK).latestRoundData(); // price
            // of stETH denominated in ETH

        if (
            block.timestamp - ethPerWeEthUpdatedAt > maxTimeFromLastUpdate
                || block.timestamp - ethPerStEthUpdatedAt > maxTimeFromLastUpdate
        ) {
            return 0; // collateral valuation is zero if oracle data is stale
        } else {
            // (ETH / weETH) / (ETH / stETH) = stETH / weETH
            uint256 stEthPerWeEth =
                ethPerWeEth.toUint256().scaleUpToWad(REDSTONE_DECIMALS).wadDivDown(ethPerStEth.toUint256()); // [wad]

            uint256 wstEthPerStEth = IWstEth(WSTETH_ADDRESS).tokensPerStEth(); // [wad]
            return stEthPerWeEth.wadMulDown(wstEthPerStEth); // [wad]
        }
    }
}
