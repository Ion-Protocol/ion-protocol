// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { ILidoWstETH, IStaderOracle, ISwellETH } from "../../src/interfaces/IProviderExchangeRate.sol";
import { ApyOracle } from "../../src/ApyOracle.sol";
import { RoundedMath } from "../../src/math/RoundedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract ApyOracleTest is Test {
    using RoundedMath for uint256;
    using SafeCast for uint256; 

    ApyOracle public oracle;
    uint256 public base;
    uint256 public firstRate;
    uint32 public constant PERIODS = 52142857;
    uint256 public constant PROVIDER_PRECISION = 18;
    uint32 public constant LOOK_BACK = 7;
    uint32 public constant ILKS = 3;
    uint32 public constant APY_PRECISION = 6;
    address public constant LIDO_CONTRACT_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STADER_CONTRACT_ADDRESS = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
    address public constant SWELL_CONTRACT_ADDRESS = 0xf951E335afb289353dc249e82926178EaC7DEd78;

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
        historicalExchangeRates[3] = uint256(19120105576959630103373453);
        oracle = new ApyOracle(historicalExchangeRates);
    }

    function _computeStaderExchangeRate(uint256 totalETHBalance, uint256 totalETHXSupply) internal pure returns (uint256) {
        uint256 decimals = 10 ** 18;
        uint256 newExchangeRate = (totalETHBalance == 0 || totalETHXSupply == 0)
            ? decimals
            : totalETHBalance * decimals / totalETHXSupply;
        return newExchangeRate;
    }

    function _getProviderExchangeRate(uint256 ilkIndex) internal returns (uint32) {
        // internal function to fetch provider exchange rate

        uint32 exchangeRate;
        uint256 DECIMAL_FACTOR = 10 ** (PROVIDER_PRECISION - APY_PRECISION);
        if (ilkIndex == 0) {
            // lido
            ILidoWstETH lido = ILidoWstETH(LIDO_CONTRACT_ADDRESS);
            exchangeRate = (lido.stEthPerToken() / DECIMAL_FACTOR).toUint32();
        } else if (ilkIndex == 1) {
            // stader
            IStaderOracle stader = IStaderOracle(STADER_CONTRACT_ADDRESS);
            (, uint256 totalETHBalance, uint256 totalETHXSupply) = stader.exchangeRate();
            exchangeRate = (_computeStaderExchangeRate(totalETHBalance, totalETHXSupply) / DECIMAL_FACTOR).toUint32();
        } else if (ilkIndex == 2) {
            // swell 
            ISwellETH swell = ISwellETH(SWELL_CONTRACT_ADDRESS);
            exchangeRate = (swell.swETHToETHRate() / DECIMAL_FACTOR).toUint32();
        } 
        return exchangeRate;
    }

    function testBitPackCorrect() external {
        assertEq(oracle.currentIndex(), uint256(0));
        assertEq(oracle.getHistory(3), uint256(19120105576959630103373453));
        assertEq(oracle.getHistoryByProvider(3, 0), uint32(1140365));    
        assertEq(oracle.getHistoryByProvider(3, 1), uint32(1007565));
        assertEq(oracle.getHistoryByProvider(3, 2), uint32(1036503));  
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
        assertEq(oracle.getHistoryByProvider(6, 0), uint32(1140918));
        assertEq(oracle.getHistoryByProvider(6, 1), uint32(1008062));
        assertEq(oracle.getHistoryByProvider(6, 2), uint32(1036819));
        assertEq(oracle.getHistoryByProvider(6, 3), uint32(0));
        assertEq(oracle.getHistoryByProvider(1, 0), uint32(1000000));
        assertEq(oracle.getHistoryByProvider(1, 1), uint32(1000000));
        assertEq(oracle.getHistoryByProvider(1, 2), uint32(1000000));
        assertEq(oracle.getHistoryByProvider(1, 3), uint32(0));
    }

    function testUpdateAll() external {
        // Query RPC nodes to get values for exchange rates and manually calculate expected Apys
        oracle.updateAll();
        assertEq(oracle.currentIndex(), uint256(1));
        assertEq(oracle.getApy(7), uint32(0));
        assertEq(oracle.getAll(), uint256(3569099747632263841051444275));
        
        assertEq(oracle.getHistoryByProvider(0, 0), uint32(1141145));
        assertEq(oracle.getHistoryByProvider(0, 1), uint32(1008252));
        assertEq(oracle.getHistoryByProvider(0, 2), uint32(1037106));
        assertEq(oracle.getHistoryByProvider(0, 3), uint32(0));
    }

    function testBuffer() external {
        assertEq(oracle.currentIndex(), uint256(0));
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        assertEq(oracle.currentIndex(), uint256(1));
        // by calling update all 8 times, we will eventually reuse the same data for exchange rate
        // thus, the periodic interest rate will be 0, leading all Apys to be 0
        assertEq(oracle.getApy(0), uint32(0)); 
        assertEq(oracle.getApy(1), uint32(0)); 
        assertEq(oracle.getApy(2), uint32(0)); 
        assertEq(oracle.getAll(), uint256(0));
    }

    function testRealAPRIncrement() external {
        // Query RPC nodes to get values for exchange rates and manually calculate expected Apys
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();
        oracle.updateAll();

        // fetch current exchangeRates and compare to expected values
        uint256 newApy;
        uint256 newExchangeRates;
        for (uint32 i = 0; i < ILKS;) {
            uint32 newExchangeRate = _getProviderExchangeRate(i);
            uint32 previousExchangeRate = oracle.getHistoryByProvider(uint256(oracle.currentIndex()), i);
            uint256 periodictInterest = uint256(newExchangeRate - previousExchangeRate)
                .roundedDiv(
                    uint256(previousExchangeRate), 
                    10 ** (APY_PRECISION + 2)
                );
            uint256 apy = (periodictInterest * PERIODS) / 10 ** APY_PRECISION;
            assert(apy <= type(uint32).max);

            // update apy and new exchange rates by using bit shifting
            newApy |= apy << (i * 32);
            newExchangeRates |= uint256(newExchangeRate) << (i * 32);
            unchecked {
                ++i;
            }
        }

        oracle.updateAll();
        // we simulate a real exchange rate increment here based on historical data
        assertEq(oracle.getAll(), newApy);
        assertEq(oracle.getHistory(0), newExchangeRates);
        assertEq(oracle.currentIndex(), uint256(0));
    }

}
