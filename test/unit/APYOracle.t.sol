// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ILidoWstETH, IStaderOracle, ISwellETH } from "../../src/interfaces/IProviderExchangeRate.sol";
import { ApyOracle } from "../../src/ApyOracle.sol";
import { RoundedMath } from "../../src/math/RoundedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

contract MockLido {
    function stEthPerToken() external pure returns (uint256) {
        // should correspond to a 1.2 exchange rate
        return uint256(1_200_000_000_000_000_000);
    }
}

contract MockStader {
    function exchangeRate()
        external
        pure
        returns (uint256 reportingBlockNumber, uint256 totalETHBalance, uint256 totalETHXSupply)
    {
        // should correspond to a 1.1 exchange rate
        return (uint256(0), uint256(1_320_000_000_000_000_000), uint256(1_200_000_000_000_000_000));
    }
}

contract MockSwell {
    function swETHToETHRate() external pure returns (uint256) {
        // should correspond to a 1.15 exchange rate
        return uint256(1_150_000_000_000_000_000);
    }
}

contract MockSwellzero {
    function swETHToETHRate() external pure returns (uint256) {
        // should correspond to a 1.15 exchange rate
        return 0;
    }
}

contract ApyOracleTest is Test {
    using RoundedMath for uint256;
    using SafeCast for uint256;

    ApyOracle public oracle;
    uint256 public base;
    uint256 public firstRate;
    address public mockSwell;

    error AlreadyUpdated();
    error OutOfBounds();
    error InvalidExchangeRate(uint256 ilkId);

    function setUp() public {
        uint256[7] memory historicalExchangeRates;
        // set custome values for testing purposes
        uint32[3] memory arr = [uint32(1_100_000), uint32(1_100_000), uint32(1_100_000)];
        base = uint256(0);
        firstRate = uint256(0);
        // bitpack values for historicalExchangeRates
        for (uint256 i = 0; i < 3; i++) {
            base |= uint256(1_000_000) << (i * 32);
            firstRate |= uint256(arr[i]) << (i * 32);
        }
        for (uint256 i = 0; i < 6; i++) {
            historicalExchangeRates[i] = base;
        }
        historicalExchangeRates[6] = firstRate;
        vm.warp(block.timestamp + 2 days);
        // init contract with mocks for lido, stader, swell
        mockSwell = address(new MockSwell());
        oracle = new ApyOracle(
            historicalExchangeRates, 
            address(new MockLido()), 
            address(new MockStader()), 
            mockSwell
        );
    }

    function testBitPackCorrect() external {
        assertEq(oracle.currentIndex(), uint256(0));
        assertEq(oracle.getHistory(6), uint256(20_291_418_485_804_970_804_300_000));
        assertEq(oracle.getHistoryByProvider(6, 0), uint32(1_100_000));
        assertEq(oracle.getHistoryByProvider(6, 1), uint32(1_100_000));
        assertEq(oracle.getHistoryByProvider(6, 2), uint32(1_100_000));
    }

    function testBasicStartup() external {
        assertEq(oracle.currentIndex(), uint256(0));
        assertEq(oracle.getApy(0), uint32(0));
        assertEq(oracle.getApy(1), uint32(0));
        assertEq(oracle.getApy(7), uint32(0));
        assertEq(oracle.getAll(), uint32(0));
        assertEq(oracle.getHistory(0), base);
        assertEq(oracle.getHistory(1), base);
        assertEq(oracle.getHistory(6), firstRate);
        assertEq(oracle.getHistoryByProvider(6, 0), uint32(1_100_000));
        assertEq(oracle.getHistoryByProvider(6, 1), uint32(1_100_000));
        assertEq(oracle.getHistoryByProvider(6, 2), uint32(1_100_000));
        assertEq(oracle.getHistoryByProvider(6, 3), uint32(0));
        assertEq(oracle.getHistoryByProvider(1, 0), uint32(1_000_000));
        assertEq(oracle.getHistoryByProvider(1, 1), uint32(1_000_000));
        assertEq(oracle.getHistoryByProvider(1, 2), uint32(1_000_000));
        assertEq(oracle.getHistoryByProvider(1, 3), uint32(0));

        // check reverts
        vm.expectRevert(OutOfBounds.selector);
        oracle.getApy(8);
        vm.expectRevert(OutOfBounds.selector);
        oracle.getHistoryByProvider(7, 0);
        vm.expectRevert(OutOfBounds.selector);
        oracle.getHistoryByProvider(0, 8);
        vm.expectRevert(OutOfBounds.selector);
        oracle.getHistory(7);
    }

    function testUpdateAll() external {
        oracle.updateAll();
        assertEq(oracle.currentIndex(), uint256(1));
        assertEq(oracle.getApy(7), uint32(0));
        assertEq(oracle.getAll(), uint256(14_427_989_077_505_037_798_101_007_540));

        assertEq(oracle.getHistoryByProvider(0, 0), uint32(1_200_000));
        assertEq(oracle.getHistoryByProvider(0, 1), uint32(1_100_000));
        assertEq(oracle.getHistoryByProvider(0, 2), uint32(1_150_000));
        assertEq(oracle.getHistoryByProvider(0, 3), uint32(0));
    }

    function testRevert() external {
        oracle.updateAll();
        vm.expectRevert(AlreadyUpdated.selector);
        oracle.updateAll();
    }

    function testBuffer() external {
        uint256 curr = block.timestamp;
        for (uint32 i = 0; i < 7; i += 1) {
            assertEq(oracle.currentIndex(), uint256(i));
            curr += 1 days;
            vm.warp(curr);
            oracle.updateAll();
        }
        assertEq(oracle.currentIndex(), uint256(0));
        // by calling update all 8 times, we will eventually reuse the same data for exchange rate
        // thus, the periodic interest rate will be 0, leading all Apys to be 0
        curr += 1 days;
        vm.warp(curr);
        oracle.updateAll();
        assertEq(oracle.getApy(0), uint32(0));
        assertEq(oracle.getApy(1), uint32(0));
        assertEq(oracle.getApy(2), uint32(0));
        assertEq(oracle.getAll(), uint256(0));
    }

    function testInvalidExchangeRate()  external {
        MockSwellzero mock = new MockSwellzero();
        vm.etch(mockSwell, address(mock).code);
        vm.expectRevert(abi.encodeWithSelector(InvalidExchangeRate.selector, 2));
        oracle.updateAll();
    }
}
