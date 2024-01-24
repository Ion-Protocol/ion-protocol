// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWeEth, IWstEth } from "../../interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "./ReserveOracle.sol";
import { WEETH_ADDRESS, WSTETH_ADDRESS } from "../../Constants.sol";
import { WadRayMath } from "../../libraries/math/WadRayMath.sol";

/**
 * @notice Reserve oracle for weETH.
 *
 * @custom:security-contact security@molecularlabs.io
 */

contract WeEthWstEthReserveOracle is ReserveOracle {
    using WadRayMath for uint256;

    address public immutable PROTOCOL_FEED;

    /**
     * @notice Creates a new `weEthwstEthReserveOracle` instance. Provides
     * the amount of wstETH equal to one weETH.
     * wstETH / wETH = eETH / weETH * ETH / eETH * wstETH / ETH.
     * ETH / eETH is 1 since eETH is rebasing. Depeg here would reflect in eETH / wETH
     * exchange rate.
     * @dev The value of weETH denominated in wstETH by the provider.
     * @param _ilkIndex of weETH.
     * @param _feeds List of alternative data sources for the weETH exchange rate.
     * @param _quorum The amount of alternative data sources to aggregate.
     * @param _maxChange Maximum percent change between exchange rate updates. [RAY]
     */
    constructor(
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum,
        uint256 _maxChange
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum, _maxChange)
    {
        _initializeExchangeRate();
    }

    /**
     * @notice Returns the exchange rate between ETH and weETH.
     * @return Exchange rate between ETH and weETH.
     */
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        // eETH / weETH * wstETH / stETH = wstETH / weETH
        // [WAD] * [WAD] / [WAD] = [WAD]
        return IWeEth(WEETH_ADDRESS).getRate().wadMulDown(IWstEth(WSTETH_ADDRESS).tokensPerStEth());
    }
}
