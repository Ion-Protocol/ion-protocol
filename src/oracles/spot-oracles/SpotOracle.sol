// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { IonPool } from "src/IonPool.sol";
import { Liquidation } from "src/Liquidation.sol";
import { RoundedMath, WAD, RAY } from "src/math/RoundedMath.sol";

import "forge-std/console2.sol";

// pushes spot price from value feeds to the IonPool contract
abstract contract SpotOracle {
    using RoundedMath for uint256;

    uint8 public immutable ilkIndex;
    uint64 public immutable ltv; // max LTV for a position (below liquidation threshold) [wad]

    IonPool public immutable ionPool;

    // --- Events ---
    event UpdateSpot(uint256 indexed spot);

    constructor(uint8 _ilkIndex, address _ionPool, uint64 _ltv) {
        ilkIndex = _ilkIndex;
        ionPool = IonPool(_ionPool);
        require(ltv < WAD); // ltv has to be less than 1
        ltv = _ltv;
    }

    // @dev overridden by collateral specific spot oracle contracts
    // @return price in [wad]
    function _getPrice() internal view virtual returns (uint256 price) { }

    // @dev external view function to see what value it would read
    // TODO: can this be `view`?
    function getPrice() external view returns (uint256 price) {
        price = _getPrice();
    }

    // @dev pushes market price multiplied by the liquidation threshold
    function updateSpot() external {
        console2.log("update spot");
        uint256 price = _getPrice(); // must be [wad]
        console2.log("price: ", price);
        uint256 spot = (ltv * price).scaleToRay(36); // [ray]
        require(spot > 0);
        console2.log("spot: ", spot);
        ionPool.updateIlkSpot(ilkIndex, spot);

        emit UpdateSpot(spot);
    }
}
