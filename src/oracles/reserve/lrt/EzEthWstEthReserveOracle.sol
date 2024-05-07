// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";
import { ReserveOracle } from "../ReserveOracle.sol";
import { RENZO_RESTAKE_MANAGER, EZETH, WSTETH_ADDRESS } from "../../../Constants.sol";

/**
 * @notice Reserve Oracle for ezETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EzEthWstEthReserveOracle is ReserveOracle {
    using WadRayMath for uint256;

    /**
     * @notice Creates a new `ezEthWstEthReserveOracle` instance. Provides
     * the amount of wstETH equal to one ezETH.
     * wstETH / ezETH = ETH / ezETH * wstETH / ETH.
     * @dev The value of ezETH denominated in wstETH by the provider.
     * @param _feeds List of alternative data sources for the ezETH exchange rate.
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

    function _getProtocolExchangeRate() internal view override returns (uint256) {
        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();
        uint256 totalSupply = EZETH.totalSupply();
        uint256 exchangeRateInEth = totalTVL.wadDivDown(totalSupply);
        return exchangeRateInEth.wadMulDown(WSTETH_ADDRESS.tokensPerStEth());
    }
}
