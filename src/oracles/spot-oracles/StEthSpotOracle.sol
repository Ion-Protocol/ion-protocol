// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { SpotOracle } from "src/oracles/spot-oracles/SpotOracle.sol"; 
import { IChainlink } from "src/interfaces/IChainlink.sol";
import "forge-std/console.sol"; 

interface IWstEth {
    function getStETHByWstETH(uint256 stEthAmount) external view returns (uint256 wstEthAmount);
}

contract StEthSpotOracle is SpotOracle {

    IChainlink immutable stEthToEthChainlink; 
    IWstEth immutable wstEth; 

    constructor(uint8 _feedDecimals, uint8 _ilkIndex, address _ionPool, address _stEthToEthChainlink, address _wstETH) SpotOracle(_feedDecimals, _ilkIndex, _ionPool) {
        stEthToEthChainlink = IChainlink(_stEthToEthChainlink);
        wstEth = IWstEth(_wstETH);
    }

    // @dev Because the collateral amount in the core contract is denominated in amount of wstETH tokens, 
    //      spot needs to equal (stETH/wstETH) * (ETH/stETH) * liquidationThreshold
    function _getPrice() internal view override returns (uint256 ethPerWstEth) {
        // get price from the protocol feed 
        uint256 ethPerStEth = stEthToEthChainlink.latestAnswer(); // price of stETH denominated in ETH        
        console.log("ethPerStEth: ", ethPerStEth); 
        // collateral * wstEthInEth = collateralInEth 
        ethPerWstEth = wstEth.getStETHByWstETH(uint256(ethPerStEth)); // stEth per wstEth 
        console.log("wstEthInEth: ", ethPerWstEth); 
        console.log("stEth per wstEth: ", wstEth.getStETHByWstETH(1e18));
    }   
}