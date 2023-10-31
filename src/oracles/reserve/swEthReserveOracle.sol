pragma solidity ^0.8.13;

import { ISwEth } from "src/interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "./ReserveOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// https://etherscan.io/token/0xf951E335afb289353dc249e82926178EaC7DEd78#readProxyContract
contract SwEthReserveOracle is ReserveOracle {
    using SafeCast for *;

    address public protocolFeed;

    // @param _quorum number of extra feeds to aggregate. If any of the feeds fail, pause the protocol.
    constructor(
        address _protocolFeed,
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum)
    {
        protocolFeed = _protocolFeed;
        exchangeRate = _getProtocolExchangeRate();
    }

    function _getProtocolExchangeRate() internal view override returns (uint72 protocolExchangeRate) {
        protocolExchangeRate = ISwEth(protocolFeed).getRate().toUint72();
    }
}
