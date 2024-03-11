// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SpotOracle } from "../SpotOracle.sol";
import { WadRayMath } from "../../../libraries/math/WadRayMath.sol";

/**
 * @notice The ezETH spot oracle denominated in wstETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EzEthWstEthSpotOracle is SpotOracle {
    using WadRayMath for uint256;

    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE; // seconds

    /**
     * @notice Creates a new `EzEthWstEthSpotOracle` instance.
     * @param _ltv The loan to value ratio for ezETH <> wstETH
     * @param _reserveOracle The associated reserve oracle.
     */
    constructor(
        uint256 _ltv,
        address _reserveOracle,
        uint256 _maxTimeFromLastUpdate
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        MAX_TIME_FROM_LAST_UPDATE = _maxTimeFromLastUpdate;
    }

    function getPrice() public view override returns (uint256) { }
}
