// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;


import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReserveOracle } from "src/oracles/reserve/ReserveOracle.sol";
import { RoundedMath, RAY } from "src/libraries/math/RoundedMath.sol";
import { console2 } from "forge-std/console2.sol";

// pushes spot price from value feeds to the IonPool contract
abstract contract SpotOracle {
    using RoundedMath for uint256;

    uint8 public immutable ilkIndex;
    uint256 public immutable ltv; // max LTV for a position (below liquidation threshold) [ray]

    ReserveOracle public immutable reserveOracle; 

    // --- Errrors --- 
    error InvalidLtv(uint256 ltv);
    error InvalidReserveOracle(address _reserveOracle); 

    constructor(uint8 _ilkIndex, uint256 _ltv, address _reserveOracle) {
        ilkIndex = _ilkIndex;
        if (_ltv > RAY) {
            revert InvalidLtv(_ltv);
        }
        if (address(_reserveOracle) == address(0)) {
            revert InvalidReserveOracle(address(_reserveOracle)); 
        }
        ltv = _ltv;
        reserveOracle = ReserveOracle(_reserveOracle);
    }

    // @dev overridden by collateral specific spot oracle contracts
    // @return price of the asset in ETH [wad]
    function getPrice() public view virtual returns (uint256 price);

    // @dev pushes market price multiplied by the LTV
    // @return spot value of the asset in ETH [ray]
    function getSpot() external view returns (uint256 spot) {
        uint256 price = getPrice(); // must be [wad]
        console2.log("price: ", price);
        uint256 exchangeRate = ReserveOracle(reserveOracle).currentExchangeRate(); 
        console2.log("exchangeRate: ", exchangeRate);   
        uint256 min = Math.min(price, exchangeRate); // [wad] min the price with reserve oracle before multiplying by ltv 
        console2.log("min: ", min);
        spot = ltv.wadMulDown(min); // [ray] * [wad] / [wad] = [ray] 
        console2.log("spot: ", spot);
    }
}
