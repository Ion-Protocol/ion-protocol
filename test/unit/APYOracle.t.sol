// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { APYOracle } from "../../src/APYOracle.sol";

contract APYOracleTest is Test {
    APYOracle public oracle;
    uint256 public base;

    function setUp() public {
        uint256[7] memory historicalExchangeRates;
        base = uint256(0);
        for (uint i = 0; i < 3; i++) {
            base |= uint256(1000000) << (i * 32);
        }
        for (uint i = 0; i < 7; i++) {
            historicalExchangeRates[i] = base;
        }
        oracle = new APYOracle(historicalExchangeRates);
    }

    function testBasicGetAPY() external {
        assertEq(oracle.currentIndex(), uint256(0));
        assertEq(oracle.getAPY(0), uint32(0));
        assertEq(oracle.getAPY(1), uint32(0));
        assertEq(oracle.getAPY(7), uint32(0));
        assertEq(oracle.getAll(), uint32(0));
        assertEq(oracle.getHistory(0), base);
        assertEq(oracle.getHistory(6), base);
        assertEq(oracle.getHistoryByProvider(0, 0), uint32(1000000));
        assertEq(oracle.getHistoryByProvider(0, 1), uint32(1000000));
        assertEq(oracle.getHistoryByProvider(0, 2), uint32(1000000));
        assertEq(oracle.getHistoryByProvider(0, 3), uint32(0));
    }

    function testUpdateAll() external {
        oracle.updateAll();
        assertEq(oracle.currentIndex(), uint256(1));
        assertEq(oracle.getAPY(7), uint32(0));
        assertEq(oracle.getAPY(0), uint32(7327736));
        assertEq(oracle.getAPY(1), uint32(419224));
        assertEq(oracle.getAPY(2), uint32(1914588));
        assertEq(oracle.getHistoryByProvider(0, 0), uint32(1140918));
        assertEq(oracle.getHistoryByProvider(0, 1), uint32(1008062));
        assertEq(oracle.getHistoryByProvider(0, 2), uint32(1036819));
        assertEq(oracle.getHistoryByProvider(0, 3), uint32(0));
    }

}
