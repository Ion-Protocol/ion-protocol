// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ReserveOracle } from "src/oracles/reserve/ReserveOracle.sol";
import { WadRayMath, RAY } from "src/libraries/math/WadRayMath.sol";

// pushes spot price from value feeds to the IonPool contract
abstract contract SpotOracle {
    using WadRayMath for uint256;

    uint256 public immutable LTV; // max LTV for a position (below liquidation threshold) [ray]
    ReserveOracle public immutable RESERVE_ORACLE;

    // --- Errors ---
    error InvalidLtv(uint256 ltv);
    error InvalidReserveOracle();

    constructor(uint256 _ltv, address _reserveOracle) {
        if (_ltv > RAY) {
            revert InvalidLtv(_ltv);
        }
        if (address(_reserveOracle) == address(0)) {
            revert InvalidReserveOracle();
        }
        LTV = _ltv;
        RESERVE_ORACLE = ReserveOracle(_reserveOracle);
    }

    // @dev overridden by collateral specific spot oracle contracts
    // @return price of the asset in ETH [wad]
    function getPrice() public view virtual returns (uint256 price);

    // @dev Gets the market price multiplied by the LTV. 
    // @return spot value of the asset in ETH [ray]
    function getSpot() external view returns (uint256 spot) {
        uint256 price = getPrice(); // must be [wad]
        uint256 exchangeRate = ReserveOracle(RESERVE_ORACLE).currentExchangeRate();

        // Min the price with reserve oracle before multiplying by ltv
        uint256 min = Math.min(price, exchangeRate); // [wad]

        spot = LTV.wadMulDown(min); // [ray] * [wad] / [wad] = [ray]
    }
}
