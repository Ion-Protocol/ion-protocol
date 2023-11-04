// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";
import { IChainlink } from "src/interfaces/IChainlink.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";

interface IRedstonePriceFeed {
    function latestAnswer() external view returns (int256 answer);
}

uint8 constant REDSTONE_DECIMALS = 8;
uint8 constant CHAINLINK_DECIMALS = 8;

contract EthXSpotOracle is SpotOracle {
    using RoundedMath for uint256;

    IRedstonePriceFeed immutable redstoneEthXPriceFeed;
    IChainlink immutable usdPerEthChainlink;

    constructor(
        uint8 _ilkIndex,
        uint256 _ltv,
        address _reserveOracle,
        address _redstoneEthXPriceFeed,
        address _usdPerEthChainlink
    )
        SpotOracle(_ilkIndex, _ltv, _reserveOracle)
    {
        redstoneEthXPriceFeed = IRedstonePriceFeed(_redstoneEthXPriceFeed);
        usdPerEthChainlink = IChainlink(_usdPerEthChainlink);
    }

    // @dev redstone oracle returns dollar value per ETHx with 6 decimals.
    //      This needs to be converted to [wad] and to ETH denomination.
    function getPrice() public view override returns (uint256 ethPerEthX) {
        // get price from the protocol feed
        // usd per ETHx

        uint256 usdPerEthX = uint256(redstoneEthXPriceFeed.latestAnswer()).scaleUpToWad(REDSTONE_DECIMALS); //

        // usd per ETH
        (, int256 _usdPerEth, , ,) = usdPerEthChainlink.latestRoundData(); // price of stETH denominated in ETH
        uint256 usdPerEth = uint256(_usdPerEth).scaleUpToWad(CHAINLINK_DECIMALS); // price of stETH denominated in ETH

        // (USD per ETHx) / (USD per ETH) = (USD per ETHx) * (ETH per USD) = ETH per ETHx
        ethPerEthX = usdPerEthX.wadDivDown(usdPerEth);
    }
}
