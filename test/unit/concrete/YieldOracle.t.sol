// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { YieldOracle, LOOK_BACK, ILK_COUNT } from "../../../src/YieldOracle.sol";

import {
    YieldOracleSharedSetup,
    WST_ETH_EXCHANGE_RATE,
    STADER_ETH_EXCHANGE_RATE,
    SWELL_ETH_EXCHANGE_RATE
} from "../../helpers/YieldOracleSharedSetup.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

contract YieldOracle_UnitTest is YieldOracleSharedSetup {
    function setUp() public override {
        vm.warp(1_696_181_435);
        super.setUp();
    }

    function test_Basic() external {
        vm.warp(block.timestamp + 1 days);

        oracle.updateAll();
        assertEq(oracle.currentIndex(), 2);

        assertEq(oracle.historicalExchangeRates(0, 0), uint64(1.2e18));
        assertEq(oracle.historicalExchangeRates(0, 1), uint64(1.1e18));
        assertEq(oracle.historicalExchangeRates(0, 2), uint64(1.15e18));

        assertEq(oracle.historicalExchangeRates(1, 0), uint64(1.2e18));
        assertEq(oracle.historicalExchangeRates(1, 1), uint64(1.1e18));
        assertEq(oracle.historicalExchangeRates(1, 2), uint64(1.15e18));

        for (uint256 i = 2; i < LOOK_BACK; i++) {
            for (uint256 j = 0; j < ILK_COUNT; j++) {
                assertEq(oracle.historicalExchangeRates(i, j), uint64(1.0e18));
            }
        }
    }

    function test_UpdateWhenIonPoolPaused() external {
        vm.warp(block.timestamp + 1 days);

        mockIonPool.pause();
        oracle.updateAll();
    }

    function test_UpdatingWithChangingExchangeRates() external {
        uint256 increaseInExchangeRate = 0.072935829352e18;
        uint256 amountOfUpdatesToTest = 10;

        uint256 newWstRate = WST_ETH_EXCHANGE_RATE;
        uint256 newStaderRate = STADER_ETH_EXCHANGE_RATE;
        uint256 newSwellRate = SWELL_ETH_EXCHANGE_RATE;
        // Update exchange rates
        for (uint256 i = 0; i < amountOfUpdatesToTest; i++) {
            vm.warp(block.timestamp + 1 days);

            newWstRate += increaseInExchangeRate;
            newStaderRate += increaseInExchangeRate;
            newSwellRate += increaseInExchangeRate;

            uint256[ILK_COUNT] memory newRates = [newWstRate, newStaderRate, newSwellRate];

            uint256 indexToUpdate = oracle.currentIndex();

            uint64[ILK_COUNT][LOOK_BACK] memory ratesBefore;
            for (uint256 j = 0; j < ILK_COUNT; j++) {
                for (uint256 k = 0; k < LOOK_BACK; k++) {
                    ratesBefore[k][j] = oracle.historicalExchangeRates(k, j);
                }
            }

            lidoOracle.setNewRate(newWstRate);
            staderOracle.setNewRate(newStaderRate);
            swellOracle.setNewRate(newSwellRate);

            oracle.updateAll();

            for (uint256 j = 0; j < ILK_COUNT; j++) {
                for (uint256 k = 0; k < LOOK_BACK; k++) {
                    if (k == indexToUpdate) {
                        assertEq(oracle.historicalExchangeRates(k, j), newRates[j]);
                    } else {
                        assertEq(oracle.historicalExchangeRates(k, j), ratesBefore[k][j]);
                    }
                }
            }
        }

        // _prettyPrintApys();
        // _prettyPrintRatesMatrix();
    }

    function test_RevertWhen_ExchangeRateIsZero() external {
        vm.warp(block.timestamp + 1 days);

        lidoOracle.setNewRate(0);
        vm.expectRevert(abi.encodeWithSelector(YieldOracle.InvalidExchangeRate.selector, 0));
        oracle.updateAll();
    }

    function test_ApyIsZeroWhenNewExchangeRateIsLessThanPrevious() external {
        vm.warp(block.timestamp + 1 days);

        lidoOracle.setNewRate(2 wei);
        oracle.updateAll();

        assertEq(oracle.apys(0), 0);
    }

    function test_RevertWhen_UpdatingMoreThanOnceADay() external {
        vm.expectRevert(YieldOracle.AlreadyUpdated.selector);
        oracle.updateAll();
    }

    function _prettyPrintApys() internal view {
        for (uint256 i = 0; i < ILK_COUNT; i++) {
            console.log("Ilk: %s", i + 1);
            console.log("APY: %s", oracle.apys(i));
            console.log("");
        }
    }

    function _prettyPrintRatesMatrix() internal view {
        for (uint256 k = 0; k < LOOK_BACK; k++) {
            console.log("Day: %s", k + 1);
            for (uint256 j = 0; j < ILK_COUNT; j++) {
                console.log(oracle.historicalExchangeRates(k, j));
            }
            console.log("");
        }
    }
}
