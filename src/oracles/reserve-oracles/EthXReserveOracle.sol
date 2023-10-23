pragma solidity ^0.8.13;

import { IStaderOracle } from "src/interfaces/IProviders.sol";
import { ReserveOracle } from "./ReserveOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { RoundedMath } from "src/math/RoundedMath.sol";
import "forge-std/console.sol"; 
// https://etherscan.io/address/0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737

uint8 constant ethXDecimals = 18;
contract EthXReserveOracle is ReserveOracle {
    using RoundedMath for uint256; 
    using SafeCast for *; 

    address public protocolFeed;

    // @param _quorum number of extra feeds to aggregate. If any of the feeds fail, pause the protocol. 
    constructor(address _protocolFeed, uint8 _ilkIndex, address[] memory _feeds, uint8 _quorum) ReserveOracle(_ilkIndex, _feeds, _quorum) {
        protocolFeed = _protocolFeed;
        exchangeRate = _getProtocolExchangeRate();
    }

    // @dev exchange rate is total LST supply divided by total underlying ETH 
    // NOTE: 
    function _getProtocolExchangeRate() internal view override returns (uint72 protocolExchangeRate) {
        (, uint256 totalEthBalance, uint256 totalEthXSupply) = IStaderOracle(protocolFeed).exchangeRate(); 
        protocolExchangeRate = totalEthBalance.wadDivDown(totalEthXSupply).toUint72();
    }
}
