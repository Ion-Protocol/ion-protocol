// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { WAD, RAY } from "src/libraries/math/WadRayMath.sol";
import { WstEthReserveOracle } from "src/oracles/reserve/WstEthReserveOracle.sol";
import { ReserveFeed } from "src/oracles/reserve/ReserveFeed.sol";
import { ReserveOracle } from "src/oracles/reserve/ReserveOracle.sol";
import { IStEth, IWstEth } from "src/interfaces/ProviderInterfaces.sol";

import { ReserveOracleSharedSetup } from "test/helpers/ReserveOracleSharedSetup.sol";

// fork tests for integrating with external contracts
contract WstEthReserveOracleForkTest is ReserveOracleSharedSetup {
    // --- stETH Reserve Oracle Test ---

    function test_WstEthReserveOracleGetProtocolExchangeRate() public {
        uint256 maxChange = 3e25; // 0.03 3%
        address[] memory feeds = new address[](3);
        uint8 quorum = 0;
        WstEthReserveOracle stEthReserveOracle =
            new WstEthReserveOracle(WSTETH, STETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 protocolExchangeRate = stEthReserveOracle.getProtocolExchangeRate();
        assertEq(protocolExchangeRate, 1_143_213_397_000_524_230, "protocol exchange rate");
    }

    function test_WstEthReserveOracleAggregation() public {
        uint256 maxChange = 3e25; // 0.03 3%

        ReserveFeed reserveFeed1 = new ReserveFeed();
        ReserveFeed reserveFeed2 = new ReserveFeed();
        ReserveFeed reserveFeed3 = new ReserveFeed();

        uint72 reserveFeed1ExchangeRate = 1.1 ether;
        uint72 reserveFeed2ExchangeRate = 1.12 ether;
        uint72 reserveFeed3ExchangeRate = 1.14 ether;

        reserveFeed1.setExchangeRate(STETH_ILK_INDEX, reserveFeed1ExchangeRate);
        reserveFeed2.setExchangeRate(STETH_ILK_INDEX, reserveFeed2ExchangeRate);
        reserveFeed3.setExchangeRate(STETH_ILK_INDEX, reserveFeed3ExchangeRate);

        address[] memory feeds = new address[](3);

        feeds[0] = address(reserveFeed1);
        feeds[1] = address(reserveFeed2);
        feeds[2] = address(reserveFeed3);

        uint8 quorum = 3;
        WstEthReserveOracle stEthReserveOracle =
            new WstEthReserveOracle(WSTETH, STETH_ILK_INDEX, feeds, quorum, maxChange);

        uint72 expectedMinExchangeRate = (reserveFeed1ExchangeRate + reserveFeed2ExchangeRate + reserveFeed3ExchangeRate) / 3;

        stEthReserveOracle.updateExchangeRate();
        uint256 protocolExchangeRate = stEthReserveOracle.currentExchangeRate();

        // should output the expected as the minimum
        assertEq(protocolExchangeRate, expectedMinExchangeRate, "protocol exchange rate");
    }

    // --- Errors ---
    function test_RevertWhen_StEthInvalidInitialization() public {
        ReserveFeed reserveFeed1 = new ReserveFeed();
        ReserveFeed reserveFeed2 = new ReserveFeed();
        ReserveFeed reserveFeed3 = new ReserveFeed();

        uint256 maxChange = 3e25; // 0.03 3%
        address[] memory feeds = new address[](3);
        feeds[0] = address(reserveFeed1);
        feeds[1] = address(reserveFeed2);
        feeds[2] = address(reserveFeed3);
        uint8 quorum = 3;

        vm.expectRevert(abi.encodeWithSelector(ReserveOracle.InvalidInitialization.selector, 0));
        new WstEthReserveOracle(WSTETH, STETH_ILK_INDEX, feeds, quorum, maxChange);
    }

    // --- Slashing Scenario ---

    /**
     * Slashing reported via the Lido oracle should report a lowered total CL_BALANCE and lead to a decrease
     * in the totalPooledEther variable within the Lido contract.
     */
    function test_StEthTotalPooledEtherPostSlashing() public {
        uint256 clBalanceDiff = 5 ether;

        uint256 totalPooledEther = IStEth(LIDO).getTotalPooledEther();
        uint256 clBalance = uint256(vm.load(LIDO, LIDO_CL_BALANCE_SLOT));

        uint256 newClBalance = clBalance - clBalanceDiff;
        vm.store(LIDO, LIDO_CL_BALANCE_SLOT, bytes32(newClBalance));
        assertEq(uint256(vm.load(LIDO, LIDO_CL_BALANCE_SLOT)), newClBalance);

        uint256 newTotalPooledEther = IStEth(LIDO).getTotalPooledEther(); // change in CL_BALANCE should change
            // totalPooledEther

        assertEq(totalPooledEther - newTotalPooledEther, clBalanceDiff);
    }

    /**
     * Slashing and the change in totalPooledEther variable should lower wstETH to stETH exchange rate.
     * 1 wstEth should equal 1 share in lido.
     * ETH per share is totalPooled Ether / totalShares.
     */
    function test_WstEthExchangeRatePostSlashing() public {
        uint256 clBalanceDiff = 1000 ether;

        uint256 clBalance = uint256(vm.load(LIDO, LIDO_CL_BALANCE_SLOT));
        uint256 totalShares = uint256(vm.load(LIDO, LIDO_TOTAL_SHARES_SLOT));

        // reduce CL_BALANCE
        uint256 newClBalance = clBalance - clBalanceDiff;
        vm.store(LIDO, LIDO_CL_BALANCE_SLOT, bytes32(newClBalance));

        uint256 newTotalPooledEther = IStEth(LIDO).getTotalPooledEther();

        uint256 expectedNewEthPerShare = 1 ether * newTotalPooledEther / totalShares; // shares * totalPooledEther /
            // totalShares [truncate quotient]

        uint256 newExchangeRate = IWstEth(WSTETH).stEthPerToken();

        assertEq(expectedNewEthPerShare, newExchangeRate, "new exchange rate");
    }

    // --- Bounding Scenario ---

    function test_WstEthReserveOracleOutputsMin() public {
        uint256 maxChange = 3e25; // 0.03 3%
        uint256 newClBalance = 0.5 ether;

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets prevExchangeRate to be the current exchangeRate in constructor
        WstEthReserveOracle stEthReserveOracle =
            new WstEthReserveOracle(WSTETH, STETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 exchangeRate = stEthReserveOracle.currentExchangeRate();
        // set Lido exchange rate to be lower
        vm.store(LIDO, LIDO_CL_BALANCE_SLOT, bytes32(newClBalance));

        stEthReserveOracle.updateExchangeRate();
        uint256 newExchangeRate = stEthReserveOracle.currentExchangeRate();

        // should output the min
        uint256 minExchangeRate = exchangeRate - ((exchangeRate * maxChange) / RAY);
        assertEq(newExchangeRate, minExchangeRate, "minimum exchange rate bound");
    }

    function test_WstEthReserveOracleOutputsMax() public {
        uint256 maxChange = 25e25; // 0.25 25%
        uint256 newClBalance = 100 * WAD * RAY;

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets currentExchange rate to be the current exchangeRate in constructor
        WstEthReserveOracle stEthReserveOracle =
            new WstEthReserveOracle(WSTETH, STETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 exchangeRate = stEthReserveOracle.currentExchangeRate();

        // set Lido exchange rate to be lower
        vm.store(LIDO, LIDO_CL_BALANCE_SLOT, bytes32(newClBalance));
        stEthReserveOracle.updateExchangeRate();

        uint256 newExchangeRate = stEthReserveOracle.currentExchangeRate();

        // should output the min
        uint256 maxExchangeRate = exchangeRate + ((exchangeRate * maxChange) / RAY);
        assertEq(newExchangeRate, maxExchangeRate, "maximum bound");
    }
}
