// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import { ILido, IWstEth } from "src/interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "./ReserveOracle.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { console2 } from "forge-std/console2.sol";

contract StEthReserveOracle is ReserveOracle {
    using SafeCast for uint256;
    using RoundedMath for uint256;

    address public immutable lido;
    address public immutable wstEth;

    constructor(
        address _lido,
        address _wstEth,
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum)
    {
        lido = _lido;
        wstEth = _wstEth;
        exchangeRate = _getProtocolExchangeRate();
    }

    // @dev converts wstETH to stETH to ETH for ETH per wstETH
    // stETH / wstETH = stEth per wstEth
    // ETH / stETH = total ether value / total stETH supply
    // ETH / wstETH = (ETH / stETH) * (stETH / wstETH)
    // NOTE: stEth might not be deployed until the offchain reserve oracle for stEth is production ready.
    // TODO: Add Lido's transient balance on top. 
    function _getProtocolExchangeRate() internal view override returns (uint72) {
        uint256 bufferedEther = ILido(lido).getBufferedEther();
        (,, uint256 beaconBalance) = ILido(lido).getBeaconStat();
        uint256 ethPerStEth = (beaconBalance + bufferedEther).wadDivDown(ILido(lido).totalSupply());
        uint256 stEthPerWstEth = IWstEth(wstEth).stEthPerToken();
        return ethPerStEth.wadMulDown(stEthPerWstEth).toUint72();
    }
}
