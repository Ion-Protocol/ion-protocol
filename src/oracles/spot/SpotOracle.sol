// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { RoundedMath, WAD } from "src/libraries/math/RoundedMath.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

// pushes spot price from value feeds to the IonPool contract
abstract contract SpotOracle {
    using RoundedMath for uint256;

    error LtvTooLarge(uint256 invalidLtv);

    uint8 public immutable ilkIndex;
    uint256 public immutable ltv; // max LTV for a position (below liquidation threshold) [wad]

    // --- Events ---

    constructor(uint8 _ilkIndex, uint256 _ltv) {
        ilkIndex = _ilkIndex;
        if (ltv > WAD) revert LtvTooLarge(_ltv);
        ltv = _ltv;
    }

    /**
     * @dev overridden by collateral specific spot oracle contracts
     * @return price of the asset in ETH [wad]
     */
    function getPrice() public view virtual returns (uint256 price) { }

    // @dev pushes market price multiplied by the liquidation threshold
    function getSpot() external view returns (uint256 spot) {
        uint256 price = getPrice(); // must be [wad]
        spot = (ltv * price).scaleToRay(36); // [ray]
    }
}
