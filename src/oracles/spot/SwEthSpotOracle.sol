// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { TickMath } from "../../libraries/uniswap/TickMath.sol";
import { UniswapOracleLibrary } from "../../libraries/uniswap/UniswapOracleLibrary.sol";
import { WAD } from "../../libraries/math/WadRayMath.sol";
import { SpotOracle } from "./SpotOracle.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @notice The swETH spot oracle.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract SwEthSpotOracle is SpotOracle {
    using Math for uint256;

    error InvalidSecondsAgo(uint32 invalidSecondsAgo);

    IUniswapV3Pool public immutable POOL;
    uint32 public immutable SECONDS_AGO;

    /**
     * @notice Creates a new `SwEthSpotOracle` instance.
     * @param _ltv The loan to value ratio for swETH.
     * @param _reserveOracle The associated reserve oracle.
     * @param _uniswapPool swETH/Eth Uniswap pool address.
     * @param _secondsAgo The TWAP period in seconds.
     */
    constructor(
        uint256 _ltv,
        address _reserveOracle,
        address _uniswapPool,
        uint32 _secondsAgo
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        if (_secondsAgo == 0) revert InvalidSecondsAgo(_secondsAgo);

        POOL = IUniswapV3Pool(_uniswapPool);
        SECONDS_AGO = _secondsAgo;
    }

    /**
     * @notice Gets the price of swETH in ETH.
     * @dev Uniswap returns price in swETH per ETH. This needs to be inversed.
     * @return ethPerSwEth price of swETH in ETH. [WAD]
     */
    function getPrice() public view override returns (uint256 ethPerSwEth) {
        (int24 arithmeticMeanTick,) = UniswapOracleLibrary.consult(address(POOL), SECONDS_AGO);
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        // swETH per ETH
        uint256 swEthPerEth = _getPriceInWadFromSqrtPriceX96(sqrtPriceX96); // [wad]
        ethPerSwEth = WAD * WAD / swEthPerEth; // [wad] * [wad] / [wad]
    }

    /**
     * @notice Converts a sqrtPriceX96 to a price in WAD.
     * @param sqrtPriceX96 Price in sqrtPriceX96.
     */
    function _getPriceInWadFromSqrtPriceX96(uint256 sqrtPriceX96) internal pure returns (uint256) {
        return (sqrtPriceX96 * sqrtPriceX96).mulDiv(WAD, 2 ** 192); // [wad]
    }
}
