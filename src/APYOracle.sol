// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ILidoWstETH, IStaderOracle, ISwellETH } from "./interfaces/IProviderExchangeRate.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { RoundedMath } from "./math/RoundedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IApyOracle } from "./interfaces/IApyOracle.sol";

// NOTE: the actual value is 52.142857
uint32 constant _PERIODS = 52_142_857;
uint256 constant _PROVIDER_PRECISION = 18;
uint32 constant _LOOK_BACK = 7;
uint32 constant _ILKS = 3;
uint32 constant _APY_PRECISION = 6;
uint256 constant _UPDATE_LOCK_LENGTH = 1 days;

contract ApyOracle is IApyOracle {
    using RoundedMath for uint256;
    using SafeCast for uint256;

    uint32 public constant PERIODS = _PERIODS;
    uint256 public constant PROVIDER_PRECISION = _PROVIDER_PRECISION;
    uint32 public constant LOOK_BACK = _LOOK_BACK;
    uint32 public constant ILKS = _ILKS;
    uint32 public constant APY_PRECISION = _APY_PRECISION;
    uint256 public constant UPDATE_LOCK_LENGTH = _UPDATE_LOCK_LENGTH;

    // store the index of current exchange rate to use for each provider
    uint256 public currentIndex;
    // store the current Apys as packed uint32s
    uint256 public apys;
    // array of packed exchange rates over relevant period where legnth is defined by t0
    // where t0 is the length of the lookback period
    uint256[LOOK_BACK] public historicalExchangeRates;
    // lido, stader, and swell contract addresses    uint256 public lastUpdated;
    address public immutable LIDO_CONTRACT_ADDRESS;
    address public immutable STADER_CONTRACT_ADDRESS;
    address public immutable SWELL_CONTRACT_ADDRESS;
    // update lock timestamp tracking variable
    uint256 public lastUpdated;

    // EVENT TYPES
    event ExchangeRate(uint256 indexed ilkIndex, uint256 exchangeRate, uint256 timestamp);
    event ApyUpdate(uint256 apys, uint256 timestamp);

    // ERROR TYPES
    error InvalidExchangeRate(uint256 ilkId);
    error AlreadyUpdated();
    error OutOfBounds();

    constructor(uint256[7] memory _historicalExchangeRates, address _lido, address _stader, address _swell) {
        historicalExchangeRates = _historicalExchangeRates;
        LIDO_CONTRACT_ADDRESS = _lido;
        STADER_CONTRACT_ADDRESS = _stader;
        SWELL_CONTRACT_ADDRESS = _swell;
        lastUpdated = block.timestamp - 2 * (UPDATE_LOCK_LENGTH);
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

    function _computeStaderExchangeRate(
        uint256 totalETHBalance,
        uint256 totalETHXSupply
    )
        internal
        pure
        returns (uint256)
    {
        uint256 decimals = 10 ** 18;
        uint256 newExchangeRate =
            (totalETHBalance == 0 || totalETHXSupply == 0) ? decimals : totalETHBalance * decimals / totalETHXSupply;
        return newExchangeRate;
    }

    function updateAll() external {
        if (lastUpdated + UPDATE_LOCK_LENGTH > block.timestamp) {
            revert AlreadyUpdated();
        }

        // read current index and exchange rates once from storage slot (2 READS)
        uint256 memoryIndex = currentIndex;
        uint256 previousExchangeRates = historicalExchangeRates[memoryIndex];

        uint256 newApy;
        uint256 newExchangeRates;
        for (uint256 i = 0; i < ILKS;) {
            uint32 newExchangeRate = _getProviderExchangeRate(i);
            uint32 previousExchangeRate = _getValueAtProviderIndex(i, previousExchangeRates);
            if (newExchangeRate == 0 || newExchangeRate < previousExchangeRate) {
                revert InvalidExchangeRate(i);
            }

            uint256 periodictInterest = uint256(newExchangeRate - previousExchangeRate).roundedDiv(
                uint256(previousExchangeRate), 10 ** (APY_PRECISION + 2)
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
        if (ilkIndex >= 8) {
            revert OutOfBounds();
        }
        return uint256(_getValueAtProviderIndex(ilkIndex, apys));
    }

    function getAll() external view returns (uint256) {
        // return all apys (1 READ)
        return apys;
    }

    // These functions should not be exposed and are only used for testing purposes

    function getHistory(uint256 lookBack) external view returns (uint256) {
        // return all historical exchange rates at given look_back (1 READ)
        if (lookBack >= LOOK_BACK) {
            revert OutOfBounds();
        }
        return historicalExchangeRates[lookBack];
    }

    function getHistoryByProvider(uint256 lookBack, uint32 ilkIndex) external view returns (uint32) {
        // return historical exchange rate for a provider (1 READ)
        if (ilkIndex >= 8 || lookBack >= LOOK_BACK) {
            revert OutOfBounds();
        }
        return _getValueAtProviderIndex(ilkIndex, historicalExchangeRates[lookBack]);
    }
}
