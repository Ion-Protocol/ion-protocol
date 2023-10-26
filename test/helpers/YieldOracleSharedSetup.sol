// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { IWstEth, IStaderOracle, ISwEth } from "src/interfaces/ProviderInterfaces.sol";
import { YieldOracle, LOOK_BACK, ILK_COUNT } from "../../src/YieldOracle.sol";

uint256 constant WST_ETH_EXCHANGE_RATE = 1.2e18;
uint256 constant STADER_ETH_EXCHANGE_RATE = 1.1e18;
uint256 constant SWELL_ETH_EXCHANGE_RATE = 1.15e18;

contract MockLido is IWstEth {
    uint256 _exchangeRate = WST_ETH_EXCHANGE_RATE;

    function stEthPerToken() external view returns (uint256) {
        return _exchangeRate;
    }

    function setNewRate(uint256 newRate) external {
        _exchangeRate = newRate;
    }
}

contract MockStader is IStaderOracle {
    uint256 _exchangeRate = STADER_ETH_EXCHANGE_RATE;

    function exchangeRate() external view returns (uint256, uint256, uint256) {
        uint256 totalEthXSupply = 1.2e18;
        return (0, totalEthXSupply * _exchangeRate / 1e18, totalEthXSupply);
    }

    function setNewRate(uint256 newRate) external {
        _exchangeRate = newRate;
    }
}

contract MockSwell is ISwEth {
    uint256 _exchangeRate = SWELL_ETH_EXCHANGE_RATE;

    function getRate() external view returns (uint256) {
        return _exchangeRate; 
    }

    function swETHToETHRate() external view returns (uint256) {
        return _exchangeRate;
    }

    function setNewRate(uint256 newRate) external {
        _exchangeRate = newRate;
    }
}

abstract contract YieldOracleSharedSetup is Test {
    YieldOracle public oracle;

    uint64 internal constant baseRate = 1e18;
    uint64[ILK_COUNT] internal recentPostUpdateRates =
        [uint64(WST_ETH_EXCHANGE_RATE), uint64(STADER_ETH_EXCHANGE_RATE), uint64(SWELL_ETH_EXCHANGE_RATE)];

    MockLido lidoOracle;
    MockStader staderOracle;
    MockSwell swellOracle;

    uint64[ILK_COUNT][LOOK_BACK] historicalExchangeRatesInitial;

    function setUp() public {
        // Warp to reasonable timestamp
        vm.warp(1_696_181_435);

        lidoOracle = new MockLido();
        staderOracle = new MockStader();
        swellOracle = new MockSwell();

        uint64[ILK_COUNT] memory baseRates;

        for (uint256 i = 0; i < ILK_COUNT; i++) {
            baseRates[i] = baseRate;
        }

        for (uint256 i = 0; i < LOOK_BACK; i++) {
            historicalExchangeRatesInitial[i] = baseRates;
        }

        oracle = new YieldOracle(
            historicalExchangeRatesInitial, 
            address(lidoOracle),
            address(staderOracle),
            address(swellOracle)
        );
    }

    function test_setUp() external {
        for (uint256 i = 0; i < historicalExchangeRatesInitial.length; i++) {
            for (uint256 j = 0; j < historicalExchangeRatesInitial[i].length; j++) {
                if (i == 0) {
                    assertEq(oracle.historicalExchangeRates(i, j), recentPostUpdateRates[j]);
                } else {
                    assertEq(oracle.historicalExchangeRates(i, j), historicalExchangeRatesInitial[i][j]);
                }
            }
        }

        assertEq(oracle.currentIndex(), 1);
    }
}
