// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.21;

// contract ReserveFeed is ReserveOracle {
//     address public protocolFeed;

//     address public immutable ilk0;
//     address public immutable ilk1;
//     address public immutable ilk2;

//     constructor(address _token, address[] memory _ilks) ReserveOracle(_token) {
//         protocolFeed = _protocolFeed;
//         exchangeRate = _getProtocolExchangeRate();
//         nextExchangeRate = exchangeRate;
//     }

//     function _getProtocolExchangeRate() internal view override returns (uint256) {
//         return wstEth(protocolFeed).exchangeRate();
//     }

// }
