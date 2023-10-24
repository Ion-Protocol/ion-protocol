// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { TickMath } from "src/oracles/spot/TickMath.sol";
import { UniswapOracleLibrary } from "src/oracles/spot/UniswapOracleLibrary.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SpotOracle } from "./SpotOracle.sol";
import { WAD } from "src/libraries/math/RoundedMath.sol";

contract UniswapHelper {
    function _getPriceX96FromSqrtPriceX96(uint256 sqrtPriceX96) public pure returns (uint256 priceX96) {
        return Math.mulDiv(sqrtPriceX96 * sqrtPriceX96, 10 ** 18, 2 ** 192); // [wad]
    }
}

contract SwEthSpotOracle is SpotOracle, UniswapHelper {
    using Math for uint256;

    IUniswapV3Pool immutable uniswapPool;
    uint32 immutable secondsAgo;

    constructor(
        uint8 _ilkIndex,
        address _ionPool,
        uint64 _ltv,
        address _uniswapPool,
        uint32 _secondsAgo
    )
        SpotOracle(_ilkIndex, _ionPool, _ltv)
    {
        uniswapPool = IUniswapV3Pool(_uniswapPool);
        secondsAgo = _secondsAgo;
    }

    // @dev
    // NOTE: Uniswap returns price in swETH per ETH. This needs to be reciprocaled.
    function getPrice() public view override returns (uint256 ethPerSwEth) {
        (int24 arithmeticMeanTick,) = UniswapOracleLibrary.consult(address(uniswapPool), secondsAgo);
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        // swETH per ETH
        uint256 swEthPerEth = _getPriceX96FromSqrtPriceX96(sqrtPriceX96); // [wad]
        ethPerSwEth = WAD * WAD / swEthPerEth; // [wad] * [wad] / [wad]
    }
}
