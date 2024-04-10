// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { EZETH, RENZO_RESTAKE_MANAGER } from "../../../Constants.sol";
import { ReserveOracle } from "../ReserveOracle.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using Math for uint256;

/**
 * @notice Reserve Oracle for PT-ezETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract EzEthPtReserveOracle is ReserveOracle {
    constructor(
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum,
        uint256 _maxChange
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum, _maxChange)
    { }

    /**
     * @dev 1 PT will be worth 1 ETH at maturity. Since we want to value the PT
     * at maturity, we need to convert 1 ETH of value into ezETH terms.
     */
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();
        uint256 totalSupply = EZETH.totalSupply();

        return totalTVL.mulDiv(1e18, totalSupply);
    }
}
