// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IRswEth } from "../../../interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "../ReserveOracle.sol";
import { WSTETH_ADDRESS, RSWETH } from "../../../Constants.sol";
import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";

/**
 * @notice Reserve oracle for rswETH.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract RswEthWstEthReserveOracle is ReserveOracle {
    using WadRayMath for uint256;

    /**
     * @notice Creates a new `rswEthwstEthReserveOracle` instance. Provides
     * the amount of wstETH equal to one rswETH.
     * wstETH / rswETH = ETH / rswETH * wstETH / ETH.
     * @dev The value of rswETH denominated in wstETH by the provider.
     * @param _ilkIndex of rswETH.
     * @param _feeds List of alternative data sources for the rswETH exchange rate.
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
     * @notice Returns the exchange rate between wstETH and rswETH.
     * @return Exchange rate between wstETH and rswETH.
     */
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return RSWETH.getRate().wadMulDown(WSTETH_ADDRESS.tokensPerStEth());
    }
}
