// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import { ILido, IWstEth } from "src/interfaces/ProviderInterfaces.sol";
import { ReserveOracle } from "./ReserveOracle.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { console2 } from "forge-std/console2.sol";

contract StEthReserveOracle is ReserveOracle {
    using RoundedMath for uint256;

    address public immutable lido;
    address public immutable wstEth;

    constructor(
        address _lido,
        address _wstEth,
        uint8 _ilkIndex,
        address[] memory _feeds,
        uint8 _quorum,
        uint256 _maxChange
    )
        ReserveOracle(_ilkIndex, _feeds, _quorum, _maxChange)
    {
        lido = _lido;
        wstEth = _wstEth;
        updateExchangeRate();
    }

    // @dev Returns the exchange rate for wstETH to stETH. This function only needs to return the
    //      wstETH to stETH exchange rate as the stETH to ETH exchange rate is 1:1.
    // NOTE: In a slashing event, the loss for the staker is represented through a decrease in the
    //       wstETH to stETH exchange rate inside the wstETH contract. The stETH to ETH ratio in
    //       the Lido contract will still remain 1:1 as it rebases.
    // stETH / wstETH = stEth per wstEth
    // ETH / stETH = total ether value / total stETH supply
    // ETH / wstETH = (ETH / stETH) * (stETH / wstETH)
    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return IWstEth(wstEth).stEthPerToken();
    }
}
