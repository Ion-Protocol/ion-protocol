// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";
import { ReserveOracle } from "../ReserveOracle.sol";
import { RENZO_RESTAKE_MANAGER, EZETH } from "../../../Constants.sol";

/**
 * @notice Reserve Oracle for ezETH denominated in WETH.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EzEthWethReserveOracle is ReserveOracle {
    using WadRayMath for uint256;

    /**
     * @notice Creates a new `ezEthWethReserveOracle` instance. Provides
     * the amount of WETH equal to one ezETH (ETH / ezETH).
     * @dev The value of ezETH denominated in WETH by the provider.
     * @param _feeds List of alternative data sources for the WETH/ezETH exchange rate.
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
        return totalTVL.wadDivDown(totalSupply);
    }
}
