// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { SwEthReserveOracle } from "src/oracles/reserve/SwEthReserveOracle.sol";
import { ISwEth } from "src/interfaces/ProviderInterfaces.sol";
import { WAD, RAY } from "src/libraries/math/RoundedMath.sol";
import { ReserveOracleSharedSetup, MockFeed } from "test/helpers/ReserveOracleSharedSetup.sol";

contract SwEthReserveOracleForkTest is ReserveOracleSharedSetup {
    // --- swETH Reserve Oracle Test ---

    function test_SwEthReserveOracleGetProtocolExchangeRate() public {
        uint256 maxChange = 3e25; // 0.03 3%
        uint8 quorum = 0;

        address[] memory feeds = new address[](3);
        SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(
            SWETH,
            SWETH_ILK_INDEX, 
            feeds, 
            quorum,
            maxChange
        );

        uint256 protocolExchangeRate = swEthReserveOracle.getProtocolExchangeRate();
        assertEq(protocolExchangeRate, 1_039_088_295_006_509_594, "protocol exchange rate");
    }

    function test_SwEthReserveOracleAggregation() public {
        MockFeed mockFeed1 = new MockFeed();
        MockFeed mockFeed2 = new MockFeed();
        MockFeed mockFeed3 = new MockFeed();

        uint256 mockFeed1ExchangeRate = 0.9 ether;
        uint256 mockFeed2ExchangeRate = 0.95 ether;
        uint256 mockFeed3ExchangeRate = 1 ether;

        mockFeed1.setExchangeRate(SWETH_ILK_INDEX, mockFeed1ExchangeRate);
        mockFeed2.setExchangeRate(SWETH_ILK_INDEX, mockFeed2ExchangeRate);
        mockFeed3.setExchangeRate(SWETH_ILK_INDEX, mockFeed3ExchangeRate);

        address[] memory feeds = new address[](3);

        feeds[0] = address(mockFeed1);
        feeds[1] = address(mockFeed2);
        feeds[2] = address(mockFeed3);

        uint8 quorum = 3;
        uint256 maxChange = 1e27; // 100%
        SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(SWETH, SWETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 expectedExchangeRate = (mockFeed1ExchangeRate + mockFeed2ExchangeRate + mockFeed3ExchangeRate) / 3;

        swEthReserveOracle.updateExchangeRate();
        uint256 actualExchangeRate = swEthReserveOracle.currentExchangeRate();

        // should output the expected as the minimum
        assertEq(actualExchangeRate, expectedExchangeRate, "mock feed exchange rate");
    }

    // verifying that the change in the swETH storage slot is reflected in getRate()
    function test_SwEthReserveOracleForkExchcangeRateChange() public {
        uint256 newRateToStore = 1 ether;
        vm.store(SWETH, SWETH_TO_ETH_RATE_SLOT, bytes32(newRateToStore));
        assertEq((vm.load(SWETH, SWETH_TO_ETH_RATE_SLOT)), bytes32(newRateToStore));

        uint256 newRate = ISwEth(SWETH).getRate();
        assertEq(newRate, newRateToStore, "new rate");
    }

    // --- Bounding Scenario ---

    function test_SwEthReserveOracleOutputsMin() public {
        uint256 maxChange = 3e25; // 0.03 3%
        uint256 newRateToStore = 0.8 ether;

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets currentExchangeRate to be the current exchangeRate in constructor
        SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(SWETH, SWETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 exchangeRate = swEthReserveOracle.currentExchangeRate();

        // set swETH exchange rate to be lower
        vm.store(SWETH, SWETH_TO_ETH_RATE_SLOT, bytes32(newRateToStore));
        swEthReserveOracle.updateExchangeRate();

        uint256 newExchangeRate = swEthReserveOracle.currentExchangeRate();

        // should output the min
        uint256 minExchangeRate = exchangeRate - ((exchangeRate * maxChange) / RAY);
        assertEq(newExchangeRate, minExchangeRate, "exchange rate bounded to the minimum");
    }

    function test_SwEthReserveOracleOutputsMax() public {
        uint256 maxChange = 25e25; // 0.25 25%
        uint256 newRateToStore = 100 ether; // above max bound

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets currentExchangeRate to be the current exchangeRate in constructor
        SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(SWETH, SWETH_ILK_INDEX, feeds, quorum,
    maxChange);

        uint256 exchangeRate = swEthReserveOracle.currentExchangeRate();

        // set Swell exchange rate to be lower
        vm.store(SWETH, SWETH_TO_ETH_RATE_SLOT, bytes32(newRateToStore));
        swEthReserveOracle.updateExchangeRate();

        uint256 newExchangeRate = swEthReserveOracle.currentExchangeRate();

        // should output the max
        uint256 maxExchangeRate = exchangeRate + ((exchangeRate * maxChange) / RAY);
        assertEq(newExchangeRate, maxExchangeRate, "exchange rate bounded to the maximum");
    }

    function test_SwEthReserveOracleOutputsUnbounded() public {
        uint256 maxChange = 5e25; // 0.05 5%

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets currentExchangeRate to be the current exchangeRate in constructor
        SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(SWETH, SWETH_ILK_INDEX, feeds, quorum,
    maxChange);

        uint256 currentExchangeRate = swEthReserveOracle.currentExchangeRate();

        uint256 newRateToStore = currentExchangeRate + 1; // within bounds

        // set Swell exchange rate to new but within bounds
        vm.store(SWETH, SWETH_TO_ETH_RATE_SLOT, bytes32(newRateToStore));
        swEthReserveOracle.updateExchangeRate();

        uint256 newExchangeRate = swEthReserveOracle.currentExchangeRate();

        // should output the newly calculated exchange rate
        assertEq(newExchangeRate, newRateToStore, "exchange rate is unbounded");
    }

    // --- Reserve Oracle Aggregation Test ---

    function test_SwEthReserveOracleGetAggregateExchangeRateMin() public {
        MockFeed mockFeed = new MockFeed();
        mockFeed.setExchangeRate(SWETH_ILK_INDEX, 1.01 ether);

        // reserve oracle
        address[] memory feeds = new address[](3);
        feeds[0] = address(mockFeed);
        uint8 quorum = 1;
        SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(
            SWETH,
            SWETH_ILK_INDEX,
            feeds,
            quorum,
            MAX_CHANGE
        );

        swEthReserveOracle.updateExchangeRate();

        // should be a min of
        // protocol exchange rate = 1.03
        // mock exchange rate = 1.01
        uint256 exchangeRate = swEthReserveOracle.currentExchangeRate();
        assertEq(exchangeRate, 1.01 ether, "min exchange rate");
    }

    function test_SwEthReserveOracleTwoFeeds() public {
        MockFeed mockFeed1 = new MockFeed();
        MockFeed mockFeed2 = new MockFeed();
        mockFeed1.setExchangeRate(SWETH_ILK_INDEX, 0.9 ether);
        mockFeed2.setExchangeRate(SWETH_ILK_INDEX, 0.8 ether);

        address[] memory feeds = new address[](3);
        feeds[0] = address(mockFeed1);
        feeds[1] = address(mockFeed2);
        uint8 quorum = 2;
        SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(
            SWETH,
            SWETH_ILK_INDEX,
            feeds,
            quorum,
            MAX_CHANGE
        );

        swEthReserveOracle.updateExchangeRate();

        uint256 expectedMinExchangeRate = (0.9 ether + 0.8 ether) / 2;

        assertEq(swEthReserveOracle.currentExchangeRate(), expectedMinExchangeRate, "min exchange rate");
    }

    function test_SwEthReserveOracleThreeFeeds() public {
        MockFeed mockFeed1 = new MockFeed();
        MockFeed mockFeed2 = new MockFeed();
        MockFeed mockFeed3 = new MockFeed();

        uint256 mockFeed1ExchangeRate = 1 ether;
        uint256 mockFeed2ExchangeRate = 1.4 ether;
        uint256 mockFeed3ExchangeRate = 1.8 ether;

        mockFeed1.setExchangeRate(SWETH_ILK_INDEX, mockFeed1ExchangeRate);
        mockFeed2.setExchangeRate(SWETH_ILK_INDEX, mockFeed2ExchangeRate);
        mockFeed3.setExchangeRate(SWETH_ILK_INDEX, mockFeed3ExchangeRate);

        address[] memory feeds = new address[](3);
        feeds[0] = address(mockFeed1);
        feeds[1] = address(mockFeed2);
        uint8 quorum = 2;
        SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(
            SWETH,
            SWETH_ILK_INDEX,
            feeds,
            quorum,
            MAX_CHANGE
        );

        swEthReserveOracle.updateExchangeRate();

        uint256 expectedMinExchangeRate = (mockFeed1ExchangeRate + mockFeed2ExchangeRate + mockFeed3ExchangeRate) / 3;
        assertEq(
            swEthReserveOracle.currentExchangeRate(), swEthReserveOracle.currentExchangeRate(), "min exchange rate"
        );
    }
}
