// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IStaderOracle } from "src/interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "./ReserveOracle.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";

// https://etherscan.io/address/0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737

uint8 constant ethXDecimals = 18;

contract EthXReserveOracle is ReserveOracle {
    using RoundedMath for uint256;

    address public protocolFeed;

    // @param _quorum number of extra feeds to aggregate. If any of the feeds fail, pause the protocol.
    constructor(
        address _protocolFeed,
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum,
        uint256 _maxChange
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum, _maxChange)
    {
        protocolFeed = _protocolFeed;
        updateExchangeRate();
    }

    // @dev exchange rate is total LST supply divided by total underlying ETH
    // NOTE:
    function _getProtocolExchangeRate() internal view override returns (uint256 protocolExchangeRate) {
        (, uint256 totalEthBalance, uint256 totalEthXSupply) = IStaderOracle(protocolFeed).exchangeRate();
        protocolExchangeRate = totalEthBalance.wadDivDown(totalEthXSupply);
    }
}
