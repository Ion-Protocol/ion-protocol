// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWstEth } from "../../interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "./ReserveOracle.sol";
import { WSTETH_ADDRESS, RSETH_LRT_ORACLE } from "../../Constants.sol";
import { WadRayMath } from "../../libraries/math/WadRayMath.sol";

/**
 * @notice Reserve oracle for rsETH.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract RsEthWstEthReserveOracle is ReserveOracle {
    using WadRayMath for uint256;

    /**
     * @notice Creates a new `rsEthwstEthReserveOracle` instance. Provides
     * the amount of wstETH equal to one rsETH.
     * wstETH / rsETH = ETH / rsETH * wstETH / ETH.
     * @dev The value of rsETH denominated in wstETH by the provider.
     * @param _ilkIndex of rsETH.
     * @param _feeds List of alternative data sources for the rsETH exchange rate.
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
     * @notice Returns the exchange rate between wstETH and rsETH.
     * @return Exchange rate between wstETH and rsETH.
     */
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return RSETH_LRT_ORACLE.rsETHPrice().wadMulDown(IWstEth(WSTETH_ADDRESS).tokensPerStEth());
    }
}
