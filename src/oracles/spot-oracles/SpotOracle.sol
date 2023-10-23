// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { IonPool } from "src/IonPool.sol";
import { Liquidation } from "src/Liquidation.sol";
import { RoundedMath, WAD, RAY } from "src/math/RoundedMath.sol";

// pushes spot price from value feeds to the IonPool contract
abstract contract SpotOracle {
    using RoundedMath for uint256;

    uint8 public immutable ilkIndex;
    uint64 public immutable ltv; // max LTV for a position (below liquidation threshold) [wad]

    IonPool public immutable ionPool;

    // --- Events ---

    constructor(uint8 _ilkIndex, address _ionPool, uint64 _ltv) {
        ilkIndex = _ilkIndex;
        ionPool = IonPool(_ionPool);
        require(ltv < WAD); // ltv has to be less than 1
        ltv = _ltv;
    }

    // @dev overridden by collateral specific spot oracle contracts
    // @return price of the asset in ETH [wad]
    function getPrice() public view virtual returns (uint256 price) { }

    // @dev pushes market price multiplied by the liquidation threshold
    function getSpot() external view returns (uint256 spot) {
        uint256 price = getPrice(); // must be [wad]
        spot = (ltv * price).scaleToRay(36); // [ray]
        require(spot > 0);
    }
}
