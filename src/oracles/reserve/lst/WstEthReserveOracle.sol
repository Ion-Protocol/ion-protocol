// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IWstEth } from "../../../interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "../ReserveOracle.sol";

/**
 * @notice Reserve oracle for wstETH.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract WstEthReserveOracle is ReserveOracle {
    address public immutable WST_ETH;

    /**
     * @notice Creates a new `WstEthReserveOracle` instance.
     * @param _wstEth wstETH contract address.
     * @param _ilkIndex of wstETH.
     * @param _feeds List of alternative data sources for the WstEth exchange rate.
     * @param _quorum The amount of alternative data sources to aggregate.
     * @param _maxChange Maximum percent change between exchange rate updates. [RAY]
     */
    constructor(
        address _wstEth,
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum,
        uint256 _maxChange
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum, _maxChange)
    {
        WST_ETH = _wstEth;
        _initializeExchangeRate();
    }

    /**
     * @notice Returns the exchange rate between wstETH and stETH.
     * @dev In a slashing event, the loss for the staker is represented through
     * a decrease in the wstETH to stETH exchange rate inside the wstETH
     * contract. The stETH to ETH ratio in the Lido contract will still remain
     * 1:1 as it rebases.
     *
     * stETH / wstETH = stEth per wstETH
     * ETH / stETH = total ether value / total stETH supply
     * ETH / wstETH = (ETH / stETH) * (stETH / wstETH)
     */
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return IWstEth(WST_ETH).stEthPerToken();
    }
}
