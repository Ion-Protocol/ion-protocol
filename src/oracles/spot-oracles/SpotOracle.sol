// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;
import { IonPool } from "src/IonPool.sol"; 
import { Liquidation } from "src/Liquidation.sol";
import { RoundedMath, RAY } from "src/math/RoundedMath.sol";

import "forge-std/console.sol"; 


// pushes spot price from value feeds to the IonPool contract 
abstract contract SpotOracle {
    using RoundedMath for uint256;

    uint8 public immutable feedDecimals; // number ex) [wad] -> 18 
    uint8 public immutable ilkIndex; 
    IonPool public immutable ionPool; 
    Liquidation public immutable liquidation; 


    // --- Events --- 
    event UpdateSpot(uint256 indexed spot); 

    constructor(uint8 _feedDecimals,  uint8 _ilkIndex, address _ionPool) {
        feedDecimals = _feedDecimals; 
        ilkIndex = _ilkIndex; 
        ionPool = IonPool(_ionPool); 

    }

    // --- Override ---
    function _getPrice() internal virtual view returns (uint256 price) {
    }   

    // @dev external view function to see what value it would read 
    // TODO: can this be `view`? 
    function getPrice() external returns (uint256 price) {
        console.log("feedDecimals: ", feedDecimals); 
        price = _getPrice().scaleToWad(feedDecimals);
    }

    // @dev pushes market price multiplied by the liquidation threshold 
    function updateSpot() external {
        uint256 price = _getPrice(); 
        price = price.scaleToWad(feedDecimals); // make sure to switch to 18 precision [wad]

        uint256 liquidationThreshold = liquidation.liquidationThresholds(ilkIndex); // [wad]
        uint256 spot = (liquidationThreshold * price).scaleToRay(36);  // [ray] 
        ionPool.updateIlkSpot(ilkIndex, spot); 

        emit UpdateSpot(spot); 
    }
}