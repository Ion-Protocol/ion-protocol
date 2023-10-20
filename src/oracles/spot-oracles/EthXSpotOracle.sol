// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { SpotOracle } from "src/oracles/spot-oracles/SpotOracle.sol";
import { IChainlink } from "src/interfaces/IChainlink.sol";
import "src/math/RoundedMath.sol";

interface IRedstonePriceFeed {
    function latestAnswer() external view returns (int256 answer);
}

uint8 constant redstoneDecimals = 8;
uint8 constant chainlinkDecimals = 8;

contract EthXSpotOracle is SpotOracle {
    using RoundedMath for uint256;

    IRedstonePriceFeed immutable redstoneEthXPriceFeed;
    IChainlink immutable usdPerEthChainlink;

    constructor(
        uint8 _ilkIndex,
        address _ionPool,
        uint64 _ltv,
        address _redstoneEthXPriceFeed,
        address _usdPerEthChainlink
    )
        SpotOracle(_ilkIndex, _ionPool, _ltv)
    {
        redstoneEthXPriceFeed = IRedstonePriceFeed(_redstoneEthXPriceFeed);
        usdPerEthChainlink = IChainlink(_usdPerEthChainlink);
    }

    // @dev redstone oracle returns dollar value per ETHx with 6 decimals.
    //      This needs to be converted to [wad] and to ETH denomination.
    function getPrice() public view override returns (uint256 ethPerEthX) {
        // get price from the protocol feed
        // usd per ETHx
        uint256 usdPerEthX = uint256(redstoneEthXPriceFeed.latestAnswer()).scaleToWad(redstoneDecimals); //
        // usd per ETH
        uint256 usdPerEth = uint256(usdPerEthChainlink.latestAnswer()).scaleToWad(chainlinkDecimals);
        // (USD per ETHx) / (USD per ETH) = (USD per ETHx) * (ETH per USD) = ETH per ETHx
        ethPerEthX = usdPerEthX.roundedWadDiv(usdPerEth);
    }
}
