// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ILidoWstETH, IStaderOracle, ISwellETH } from "./interfaces/IProviderExchangeRate.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { RoundedMath } from "./math/RoundedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IApyOracle } from "./interfaces/IApyOracle.sol";

contract ApyOracle is IApyOracle {
    using RoundedMath for uint256;
    using SafeCast for uint256; 

    // store the index of current exchange rate to use for each provider
    uint256 public currentIndex;
    // store the current Apys as packed uint32s
    uint256 public apys;
    // array of packed exchange rates over relevant period where legnth is defined by t0
    // where t0 is the length of the lookback period
    uint256[7] public historicalExchangeRates;
    // lido, stader, and swell contract addresses
    uint256 public lastUpdated;

    // MAINNET ADDRESSES
    // address public constant LIDO_CONTRACT_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    // address public constant STADER_CONTRACT_ADDRESS = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
    // address public constant SWELL_CONTRACT_ADDRESS = 0xf951E335afb289353dc249e82926178EaC7DEd78;

    // TESTNET ADDRESSES (GOERLI)
    address public constant LIDO_CONTRACT_ADDRESS = 0x6320cD32aA674d2898A68ec82e869385Fc5f7E2f;
    address public constant STADER_CONTRACT_ADDRESS = 0x22F8E700ff3912f3Caba5e039F6dfF1a24390E80;
    address public constant SWELL_CONTRACT_ADDRESS = 0x8bb383A752Ff3c1d510625C6F536E3332327068F;

    // NOTE: the actual value is 52.142857
    uint32 public constant PERIODS = 52142857;
    uint256 public constant PROVIDER_PRECISION = 18;
    uint32 public constant LOOK_BACK = 7;
    uint32 public constant ILKS = 3;
    uint32 public constant APY_PRECISION = 6;
    uint256 public constant UPDATE_LOCK_LENGTH = 1 days;

    // EVENT TYPES
    event ExchangeRate(uint256 indexed ilkIndex, uint256 exchangeRate, uint256 timestamp);
    event ApyUpdate(uint256 apys, uint256 timestamp);

    // ERROR TYPES
    error InvalidExchangeRate(uint256 ilkId);
    error AlreadyUpdated();

    constructor(uint256[7] memory _historicalExchangeRates) {
        historicalExchangeRates = _historicalExchangeRates;
        lastUpdated = block.timestamp - UPDATE_LOCK_LENGTH;
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
        emit ExchangeRate(ilkIndex, exchangeRate, block.timestamp);
        return exchangeRate;
    }

    function _getValueAtProviderIndex(uint256 ilkIndex, uint256 values) internal pure returns (uint32) {
        // bit shifting to the providerID to get the specific uint32 in values
        return uint32(values >> (ilkIndex * 32));
    }

    function _computeStaderExchangeRate(uint256 totalETHBalance, uint256 totalETHXSupply) internal pure returns (uint256) {
        uint256 decimals = 10 ** 18;
        uint256 newExchangeRate = (totalETHBalance == 0 || totalETHXSupply == 0)
            ? decimals
            : totalETHBalance * decimals / totalETHXSupply;
        return newExchangeRate;
    }

    function updateAll() external {
        if (lastUpdated + UPDATE_LOCK_LENGTH < block.timestamp) {
            revert AlreadyUpdated();
        }

        // read current index and exchange rates once from storage slot (2 READS)
        uint256 memoryIndex = currentIndex;
        uint256 previousExchangeRates = historicalExchangeRates[memoryIndex];

        uint256 newApy;
        uint256 newExchangeRates;
        for (uint256 i = 0; i < ILKS;) {
            uint32 newExchangeRate = _getProviderExchangeRate(i);
            // TODO: add more checks?
            if (newExchangeRate == 0) {
                revert InvalidExchangeRate(i);
            }

            uint32 previousExchangeRate = _getValueAtProviderIndex(i, previousExchangeRates);
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

        // update Apy, history with new exchangeRates, and currentIndex (3 WRITES)
        apys = newApy;
        historicalExchangeRates[memoryIndex] = newExchangeRates;
        currentIndex = (currentIndex + 1) % LOOK_BACK;
        lastUpdated = block.timestamp;
        emit ApyUpdate(newApy, block.timestamp);
    }

    function getApy(uint256 ilkIndex) external view returns (uint256) {
        // read provider apy by using bit shifting (1 READ)
        assert(ilkIndex < 8);
        return uint256( _getValueAtProviderIndex(ilkIndex, apys));
    }

    function getAll() external view returns (uint256) {
        // return all apys (1 READ)
        return apys;
    }

    // These functions should not be exposed and are only used for testing purposes
    
    function getHistory(uint256 lookBack) external view returns (uint256) {
        // return all historical exchange rates at given look_back (1 READ)
        assert(lookBack < LOOK_BACK);
        return historicalExchangeRates[lookBack];
    }

    function getHistoryByProvider(uint256 lookBack, uint32 ilkIndex) external view returns (uint32) {
        // return historical exchange rate for a provider (1 READ)
        assert (ilkIndex < 8);
        assert(lookBack < LOOK_BACK);
        return _getValueAtProviderIndex(ilkIndex, historicalExchangeRates[lookBack]);
    }
    

}