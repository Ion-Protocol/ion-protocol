// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WEETH_ADDRESS } from "../../../Constants.sol";
import { ReserveOracle } from "../ReserveOracle.sol";

/**
 * @notice Reserve Oracle for PT-weETH
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract WeEthPtReserveOracle is ReserveOracle {
    constructor(
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum,
        uint256 _maxChange
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum, _maxChange)
    { }

    /**
     * @dev 1 PT will be worth 1 eETH at maturity. Since we want to value the PT
     * at maturity, we need to convert 1 eETH of value into weETH terms.
     */
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return WEETH_ADDRESS.getWeETHByeETH(1e18);
    }
}
