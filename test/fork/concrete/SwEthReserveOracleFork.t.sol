// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { SwEthReserveOracle } from "src/oracles/reserve/SwEthReserveOracle.sol";
import { ReserveOracleSharedSetup, MockFeed } from "test/helpers/ReserveOracleSharedSetup.sol";

contract SwEthReserveOracleForkTest is ReserveOracleSharedSetup {
    // --- swETH Reserve Oracle Test ---

    function test_SwEthReserveOracleGetProtocolExchangeRate() public {
        uint256 maxChange = 3e25; // 0.03 3%
        uint8 ilkIndex = 0;
        uint8 quorum = 0;

        address[] memory feeds = new address[](3);
        SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(
            SWETH_PROTOCOL_FEED,
            ilkIndex, 
            feeds, 
            quorum,
            maxChange
        );

        uint256 protocolExchangeRate = swEthReserveOracle.getProtocolExchangeRate();
        assertEq(protocolExchangeRate, 1_039_088_295_006_509_594, "protocol exchange rate");
    }

    function test_SwEthReserveOracleAggregation() public {
        uint8 ilkIndex = 0;

        MockFeed mockFeed1 = new MockFeed();
        MockFeed mockFeed2 = new MockFeed();
        MockFeed mockFeed3 = new MockFeed();

        uint256 mockFeed1ExchangeRate = 0.9 ether;
        uint256 mockFeed2ExchangeRate = 0.95 ether;
        uint256 mockFeed3ExchangeRate = 1 ether;

        mockFeed1.setExchangeRate(ilkIndex, mockFeed1ExchangeRate);
        mockFeed2.setExchangeRate(ilkIndex, mockFeed2ExchangeRate);
        mockFeed3.setExchangeRate(ilkIndex, mockFeed3ExchangeRate);

        address[] memory feeds = new address[](3);

        feeds[0] = address(mockFeed1);
        feeds[1] = address(mockFeed2);
        feeds[2] = address(mockFeed3);

        uint8 quorum = 3;
        uint256 maxChange = 1e27; // 100%
        SwEthReserveOracle swEthReserveOracle =
            new SwEthReserveOracle(SWETH_PROTOCOL_FEED, ilkIndex, feeds, quorum, maxChange);

        uint256 expectedExchangeRate = (mockFeed1ExchangeRate + mockFeed2ExchangeRate + mockFeed3ExchangeRate) / 3;

        uint256 actualExchangeRate = swEthReserveOracle.getExchangeRate();

        // should output the expected as the minimum
        assertEq(actualExchangeRate, expectedExchangeRate, "mock feed exchange rate");
    }

    // --- Bounding Scenario ---

    // function test_SwEthReserveOracleOutputsMin() public {
    //     uint256 maxChange = 3e25; // 0.03 3%

    //     uint8 ilkIndex = 0;
    //     address[] memory feeds = new address[](3);
    //     uint8 quorum = 0;

    //     // sets prevExchangeRate to be the current exchangeRate in constructor
    //     StEthReserveOracle stEthReserveOracle =
    //         new StEthReserveOracle(LIDO, WSTETH, ilkIndex, feeds, quorum, maxChange);

    //     uint256 exchangeRate = swEthReserveOracle.prevExchangeRate();

    //     // set swETH exchange rate to be lower
    //     vm.store(SWETH, )
    //     vm.store(LIDO, LIDO_CL_BALANCE_SLOT, bytes32(newClBalance));

    //     // should output the min
    //     uint256 minExchangeRate = exchangeRate - ((exchangeRate * maxChange) / RAY);
    //     assertEq(newExchangeRate, minExchangeRate, "minimum exchange rate bound");
    // }

    // function test_StEthReserveOracleOutputsMax() public {
    //     uint256 maxChange = 25e25; // 0.25 25%
    //     uint256 newClBalance = 100 * WAD * RAY;

    //     uint256 clBalance = uint256(vm.load(LIDO, LIDO_CL_BALANCE_SLOT));

    //     uint8 ilkIndex = 0;
    //     address[] memory feeds = new address[](3);
    //     uint8 quorum = 0;

    //     // sets prevExchangeRate to be the current exchangeRate in constructor
    //     StEthReserveOracle stEthReserveOracle = new StEthReserveOracle(LIDO, WSTETH, ilkIndex, feeds, quorum,
    // maxChange);

    //     uint256 exchangeRate = stEthReserveOracle.prevExchangeRate();

    //     // set Lido exchange rate to be lower
    //     vm.store(LIDO, LIDO_CL_BALANCE_SLOT, bytes32(newClBalance));

    //     uint256 wstEthExchangeRate = IWstEth(WSTETH).stEthPerToken();

    //     uint256 newExchangeRate = stEthReserveOracle.getExchangeRate();

    //     // should output the min
    //     uint256 maxExchangeRate = exchangeRate + ((exchangeRate * maxChange) / RAY);
    //     assertEq(newExchangeRate, maxExchangeRate, "maximum bound");
    // }
}
