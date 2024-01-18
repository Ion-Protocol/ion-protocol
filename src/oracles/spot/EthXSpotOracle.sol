// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";
import { IChainlink } from "src/interfaces/IChainlink.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";

interface IRedstonePriceFeed {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

uint8 constant REDSTONE_DECIMALS = 8;
uint8 constant CHAINLINK_DECIMALS = 8;

contract EthXSpotOracle is SpotOracle {
    using WadRayMath for uint256;

    IRedstonePriceFeed public immutable REDSTONE_ETHX_PRICE_FEED;
    IChainlink public immutable USD_PER_ETH_CHAINLINK;

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

    // @notice Gets the price of ETHx in ETH.
    // @dev redstone oracle returns dollar value per ETHx with 6 decimals.
    // This needs to be converted to [wad] and to ETH denomination.
    // @return ethPerEthX price of ETHx in ETH [wad]
    function getPrice() public view override returns (uint256 ethPerEthX) {
        // get price from the protocol feed
        // usd per ETHx
        (, int256 answer,,,) = REDSTONE_ETHX_PRICE_FEED.latestRoundData();

        uint256 usdPerEthX = uint256(answer).scaleUpToWad(REDSTONE_DECIMALS); //

        // usd per ETH
        (, int256 _usdPerEth,,,) = USD_PER_ETH_CHAINLINK.latestRoundData(); // price of stETH denominated in ETH
        uint256 usdPerEth = uint256(_usdPerEth).scaleUpToWad(CHAINLINK_DECIMALS); // price of stETH denominated in ETH

        // (USD per ETHx) / (USD per ETH) = (USD per ETHx) * (ETH per USD) = ETH per ETHx
        ethPerEthX = usdPerEthX.wadDivDown(usdPerEth);
    }
}
