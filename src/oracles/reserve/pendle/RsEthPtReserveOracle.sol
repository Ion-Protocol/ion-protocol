// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RSETH_LRT_ORACLE } from "../../../Constants.sol";
import { ReserveOracle } from "../ReserveOracle.sol";

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
     * @dev 1 PT will be worth 1 ETH at maturity. Since we want to value the PT
     * at maturity, we need to convert 1 ETH of value into rsETH terms.
     */
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return RSETH_LRT_ORACLE.rsETHPrice();
    }
}
