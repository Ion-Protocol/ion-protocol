// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ILidoWstETH, IStaderOracle, ISwellETH } from "./interfaces/IProviderExchangeRate.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

contract APYOracle {
    // store the index of current exchange rate to use for each provider
    uint256 public currentIndex;
    // store the current APYs as packed uint32s
    uint256 public apys;
    // array of packed exchange rates over relevant period where legnth is defined by t0
    // where t0 is the length of the lookback period
    uint256[7] public historicalExchangeRates;
    // lido, stader, and swell contract addresses
    address public constant LIDO_CONTRACT_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STADER_CONTRACT_ADDRESS = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
    address public constant SWELL_CONTRACT_ADDRESS = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    // NOTE: the actual value is 52.142857
    uint32 public constant PERIODS = 52;
    uint32 public constant DECIMAL_FACTOR = 10 ** 12;
    uint32 public constant LOOK_BACK = 7;
    uint32 public constant ILKS = 3;

    constructor(uint256[7] memory _historicalExchangeRates) {
        currentIndex = uint256(0);
        apys = uint256(0);
        historicalExchangeRates = _historicalExchangeRates;
    }

    function _getProviderExchangeRate(uint32 index) internal returns (uint32) {
        // internal function to fetch provider exchange rate

        uint32 exchangeRate = uint32(0);
        if (index == 0) {
            // lido
            ILidoWstETH lido = ILidoWstETH(LIDO_CONTRACT_ADDRESS);
            exchangeRate = uint32(lido.stEthPerToken() / DECIMAL_FACTOR); 
        } else if (index == 1) {
            // stader
            IStaderOracle stader = IStaderOracle(STADER_CONTRACT_ADDRESS);
            (uint256 reportingBlockNumber, uint256 totalETHBalance, uint256 totalETHXSupply) = stader.exchangeRate();
            exchangeRate = uint32(_computeStaderExchangeRate(totalETHBalance, totalETHXSupply) / DECIMAL_FACTOR);
        } else if (index == 2) {
            // swell 
            ISwellETH swell = ISwellETH(SWELL_CONTRACT_ADDRESS);
            exchangeRate = uint32(swell.swETHToETHRate() / DECIMAL_FACTOR);
        } 
        console.log("exchangeRate for", index, exchangeRate);
        return exchangeRate;
    }

    function _getValueAtProviderIndex(uint32 providerId, uint256 values) internal pure returns (uint32) {
        // bit shifting to the providerID to get the specific uint32 in values
        return uint32(values >> (providerId * 32));
    }

    function _computeStaderExchangeRate(uint256 totalETHBalance, uint256 totalETHXSupply) internal pure returns (uint256) {
        uint256 decimals = 10 ** 18;
        uint256 newExchangeRate = (totalETHBalance == 0 || totalETHXSupply == 0)
            ? decimals
            : totalETHBalance * decimals / totalETHXSupply;
        return newExchangeRate;
    }

    function updateAll() external {
        // read current index and exchange rates once from storage slot (2 READS)
        uint256 memoryIndex = currentIndex;
        uint256 previousExchangeRates = historicalExchangeRates[memoryIndex];

        uint256 newAPY = uint256(0);
        uint256 newExchangeRates = uint256(0);
        uint32 newExchangeRate;
        uint32 previousExchangeRate; 
        for (uint32 i = 0; i < ILKS; i++) {
            newExchangeRate = _getProviderExchangeRate(i);
            // TODO: add more checks?
            if (newExchangeRate <= 0) {
                revert(string(abi.encodePacked("Invalid exchange rate extracted from provider ", i)));
            }
            previousExchangeRate = _getValueAtProviderIndex(i, previousExchangeRates);
            console.log("EXCHANGE RATE DIFFERENCE", (newExchangeRate - previousExchangeRate));
            uint32 apy = ((newExchangeRate - previousExchangeRate) * PERIODS);
            // update apy and new exchange rates by using bit shifting
            console.log("NEW APY", apy);
            newAPY |= uint256(apy) << (i * 32);
            newExchangeRates |= uint256(newExchangeRate) << (i * 32);
        }

        // update APY, history with new exchangeRates, and currentIndex (3 WRITES)
        apys = newAPY;
        historicalExchangeRates[memoryIndex] = newExchangeRates;
        currentIndex = (currentIndex + 1) % LOOK_BACK;
    }

    function getAPY(uint32 providerId) external view returns (uint32) {
        // read provider apy by using bit shifting (1 READ)
        return _getValueAtProviderIndex(providerId, apys);
    }

    function getAll() external view returns (uint256) {
        // return all apys (1 READ)
        return apys;
    }

    function getHistory(uint256 lookBack) external view returns (uint256) {
        // return historical exchange rates (1 READ)
        return historicalExchangeRates[lookBack];
    }

    function getHistoryByProvider(uint256 lookBack, uint32 providerId) external view returns (uint32) {
        // return historical exchange rates (1 READ)
        return _getValueAtProviderIndex(providerId, historicalExchangeRates[lookBack]);
    }
}