// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ApyOracle } from "../../src/ApyOracle.sol";

contract ApyOracleTest is Test {
    ApyOracle public oracle;
    uint256 public base;
    uint256 public firstRate;

    function setUp() public {
        uint256[7] memory historicalExchangeRates;
        uint32[3] memory arr = [uint32(1140918), uint32(1008062), uint32(1036819)];
        base = uint256(0);
        firstRate = uint256(0);
        for (uint i = 0; i < 3; i++) {
            base |= uint256(1000000) << (i * 32);
            firstRate |= uint256(arr[i]) << (i * 32);
        }
        for (uint i = 0; i < 6; i++) {
            historicalExchangeRates[i] = base;
        }
        historicalExchangeRates[6] = firstRate;
        oracle = new ApyOracle(historicalExchangeRates);
    }

    // function testBasicStartup() external {
    //     assertEq(oracle.currentIndex(), uint256(0));
    //     assertEq(oracle.getApy(0), uint32(0));
    //     assertEq(oracle.getApy(1), uint32(0));
    //     assertEq(oracle.getApy(7), uint32(0));
    //     assertEq(oracle.getAll(), uint32(0));
    //     assertEq(oracle.getHistory(0), base);
    //     assertEq(oracle.getHistory(1), base);
    //     assertEq(oracle.getHistory(6), firstRate);
    //     assertEq(oracle.getHistoryByProvider(6, 0), uint32(1140918));
    //     assertEq(oracle.getHistoryByProvider(6, 1), uint32(1008062));
    //     assertEq(oracle.getHistoryByProvider(6, 2), uint32(1036819));
    //     assertEq(oracle.getHistoryByProvider(6, 3), uint32(0));
    //     assertEq(oracle.getHistoryByProvider(1, 0), uint32(1000000));
    //     assertEq(oracle.getHistoryByProvider(1, 1), uint32(1000000));
    //     assertEq(oracle.getHistoryByProvider(1, 2), uint32(1000000));
    //     assertEq(oracle.getHistoryByProvider(1, 3), uint32(0));
    // }

    // function testUpdateAll() external {
    //     // Query RPC nodes to get values for exchange rates and manually calculate expected Apys
    //     oracle.updateAll();
    //     assertEq(oracle.currentIndex(), uint256(1));
    //     assertEq(oracle.getApy(7), uint32(0));
    //     assertEq(oracle.getApy(0), uint32(733200000));
    //     assertEq(oracle.getApy(1), uint32(42120000));
    //     assertEq(oracle.getApy(2), uint32(191880000));

    //     uint256 test = uint256(0);
    //     test |= uint256(7333716) << (0 * 32);
    //     test |= uint256(424944) << (1 * 32);
    //     test |= uint256(1922596) << (2 * 32);
    //     assertEq(oracle.getAll(), test);

        
    //     // assertEq(oracle.getHistoryByProvider(0, 0), uint32(1141033));
    //     // assertEq(oracle.getHistoryByProvider(0, 1), uint32(1008172));
    //     // assertEq(oracle.getHistoryByProvider(0, 2), uint32(1036973));
    //     // assertEq(oracle.getHistoryByProvider(0, 3), uint32(0));
    // }

    // function testBuffer() external {
    //     assertEq(oracle.currentIndex(), uint256(0));
    //     oracle.updateAll();
    //     oracle.updateAll();
    //     oracle.updateAll();
    //     oracle.updateAll();
    //     oracle.updateAll();
    //     oracle.updateAll();
    //     oracle.updateAll();
    //     oracle.updateAll();
    //     assertEq(oracle.currentIndex(), uint256(1));
    //     // by calling update all 8 times, we will eventually reuse the same data for exchange rate
    //     // thus, the periodic interest rate will be 0, leading all Apys to be 0
    //     assertEq(oracle.getApy(0), uint32(0)); 
    //     assertEq(oracle.getApy(1), uint32(0)); 
    //     assertEq(oracle.getApy(2), uint32(0)); 
    //     assertEq(oracle.getAll(), uint256(0));
    // }

    function testRealAPRIncrement() external {
        // Query RPC nodes to get values for exchange rates and manually calculate expected Apys
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        // we simulate a real exchange rate increment here based on historical data
        assertEq(oracle.getApy(0), uint32(5980)); 
        assertEq(oracle.getApy(1), uint32(5720)); 
        assertEq(oracle.getApy(2), uint32(8008)); 
        assertEq(oracle.currentIndex(), uint256(0));
    }

}
