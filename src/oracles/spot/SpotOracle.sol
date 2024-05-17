// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ReserveOracle } from "../../oracles/reserve/ReserveOracle.sol";
import { WadRayMath, RAY } from "../../libraries/math/WadRayMath.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @notice The `SpotOracle` is supposed to reflect the current market price of a
 * collateral asset. It is used by `IonPool` to determine the health factor of a
 * vault as a user is opening or closing a position.
 *
 * NOTE: The price data provided by this contract is not used by the liquidation
 * module at all.
 *
 * The spot price will also always be bounded by the collateral's corresponding
 * reserve oracle price to ensure that a user can never open position that is
 * directly liquidatable.
 *
 * @custom:security-contact security@molecularlabs.io
 */
abstract contract SpotOracle {
    using WadRayMath for uint256;

    uint256 public immutable LTV; // max LTV for a position (below liquidation threshold) [ray]
    ReserveOracle public immutable RESERVE_ORACLE;

    // --- Errors ---
    error InvalidLtv(uint256 ltv);
    error InvalidReserveOracle();

    /**
     * @notice Creates a new `SpotOracle` instance.
     * @param _ltv Loan to value ratio for the collateral.
     * @param _reserveOracle Address for the associated reserve oracle.
     */
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

    /**
     * @notice Gets the price of the collateral asset in ETH.
     * @dev Overridden by collateral specific spot oracle contracts.
     * @return price of the asset in ETH. [WAD]
     */
    function getPrice() public view virtual returns (uint256 price);

    // @dev Gets the market price multiplied by the LTV.
    // @return spot value of the asset in ETH [ray]

    /**
     * @notice Gets the risk-adjusted market price.
     * @return spot The risk-adjusted market price.
     */
    function getSpot() external view returns (uint256 spot) {
        uint256 price = getPrice(); // must be [wad]
        uint256 exchangeRate = RESERVE_ORACLE.currentExchangeRate();

        // Min the price with reserve oracle before multiplying by ltv
        uint256 min = Math.min(price, exchangeRate); // [wad]

        spot = LTV.wadMulDown(min); // [ray] * [wad] / [wad] = [ray]
    }
}
