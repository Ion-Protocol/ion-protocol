// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "src/libraries/uniswap/TickMath.sol";
import { UniswapOracleLibrary } from "src/libraries/uniswap/UniswapOracleLibrary.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SpotOracle } from "./SpotOracle.sol";
import { WAD } from "src/libraries/math/RoundedMath.sol";

contract SwEthSpotOracle is SpotOracle {
    using Math for uint256;

    IUniswapV3Pool immutable POOL;
    uint32 immutable SECONDS_AGO;

    constructor(uint8 _ilkIndex, uint256 _ltv, address _reserveOracle, address _uniswapPool, uint32 _secondsAgo) SpotOracle(_ilkIndex, _ltv, _reserveOracle) {
        POOL = IUniswapV3Pool(_uniswapPool);
        SECONDS_AGO = _secondsAgo;
    }

    // @dev
    // NOTE: Uniswap returns price in swETH per ETH. This needs to be reciprocaled.
    function getPrice() public view override returns (uint256 ethPerSwEth) {
        (int24 arithmeticMeanTick,) = UniswapOracleLibrary.consult(address(POOL), SECONDS_AGO);
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        // swETH per ETH
        uint256 swEthPerEth = _getPriceX96FromSqrtPriceX96(sqrtPriceX96); // [wad]
        ethPerSwEth = WAD * WAD / swEthPerEth; // [wad] * [wad] / [wad]
    }

    function _getPriceX96FromSqrtPriceX96(uint256 sqrtPriceX96) internal pure returns (uint256 priceX96) {
        return (sqrtPriceX96 * sqrtPriceX96).mulDiv(WAD, 2 ** 192); // [wad]
    }
}
