// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SpotOracle } from "../../oracles/spot/SpotOracle.sol";
import { IChainlink } from "../../interfaces/IChainlink.sol";
import { WadRayMath } from "../../libraries/math/WadRayMath.sol";

interface IRedstonePriceFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

uint8 constant REDSTONE_DECIMALS = 8;
uint8 constant CHAINLINK_DECIMALS = 8;

/**
 * @notice The ETHx spot oracle.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EthXSpotOracle is SpotOracle {
    using WadRayMath for uint256;

    IRedstonePriceFeed public immutable REDSTONE_ETHX_PRICE_FEED;
    IChainlink public immutable USD_PER_ETH_CHAINLINK;

    /**
     * @notice Creates a new `EthXSpotOracle` instance.
     * @param _ltv The loan to value ratio for ETHX.
     * @param _reserveOracle The associated reserve oracle.
     * @param _redstoneEthXPriceFeed The redstone price feed for ETHx/USD.
     * @param _usdPerEthChainlink The chainlink price feed for ETH/USD.
     */
    constructor(
        uint256 _ltv,
        address _reserveOracle,
        address _redstoneEthXPriceFeed,
        address _usdPerEthChainlink
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        REDSTONE_ETHX_PRICE_FEED = IRedstonePriceFeed(_redstoneEthXPriceFeed);
        USD_PER_ETH_CHAINLINK = IChainlink(_usdPerEthChainlink);
    }

    /**
     * @notice Gets the price of ETHx in ETH.
     * @dev Redstone oracle returns dollar value per ETHx with 6 decimals. This
     * needs to be converted to a WAD and to ETH denomination.
     * @return ethPerEthX price of ETHx in ETH. [WAD]
     */
    function getPrice() public view override returns (uint256 ethPerEthX) {
        // get price from the protocol feed
        // usd per ETHx
        (, int256 answer,,,) = REDSTONE_ETHX_PRICE_FEED.latestRoundData();

        uint256 usdPerEthX = uint256(answer).scaleUpToWad(REDSTONE_DECIMALS);

        // usd per ETH
        (, int256 _usdPerEth,,,) = USD_PER_ETH_CHAINLINK.latestRoundData(); // price of stETH denominated in ETH
        uint256 usdPerEth = uint256(_usdPerEth).scaleUpToWad(CHAINLINK_DECIMALS); // price of stETH denominated in ETH

        // (USD per ETHx) / (USD per ETH) = (USD per ETHx) * (ETH per USD) = ETH per ETHx
        ethPerEthX = usdPerEthX.wadDivDown(usdPerEth);
    }
}
