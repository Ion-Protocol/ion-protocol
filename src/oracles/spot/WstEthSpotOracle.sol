// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";
import { IChainlink } from "src/interfaces/IChainlink.sol";

interface IWstEth {
    function getStETHByWstETH(uint256 stEthAmount) external view returns (uint256 wstEthAmount);
}

contract WstEthSpotOracle is SpotOracle {
    IChainlink immutable ST_ETH_TO_ETH_CHAINLINK;
    IWstEth immutable WST_ETH;

    constructor(
        uint256 _ltv,
        address _reserveOracle,
        address _stEthToEthChainlink,
        address _wstETH
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        ST_ETH_TO_ETH_CHAINLINK = IChainlink(_stEthToEthChainlink);
        WST_ETH = IWstEth(_wstETH);
    }

    // @dev Because the collateral amount in the core contract is denominated in amount of wstETH tokens,
    //      spot needs to equal (stETH/wstETH) * (ETH/stETH) * liquidationThreshold
    // NOTE: If the beaconchain reserve decreases, the wstEth to stEth conversion will be directly impacted,
    //       but the stEth to Eth conversion will simply be determined by the chainlink price oracle.
    function getPrice() public view override returns (uint256 ethPerWstEth) {
        // get price from the protocol feed
        (, int256 _ethPerStEth,,,) = ST_ETH_TO_ETH_CHAINLINK.latestRoundData(); // price of stETH denominated in ETH
        uint256 ethPerStEth = uint256(_ethPerStEth);
        // collateral * wstEthInEth = collateralInEth
        ethPerWstEth = WST_ETH.getStETHByWstETH(uint256(ethPerStEth)); // stEth per wstEth
    }
}
