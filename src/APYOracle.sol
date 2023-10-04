// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ILidoWstEth, IStaderOracle, ISwellEth } from "./interfaces/ProviderInterfaces.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { RoundedMath } from "./math/RoundedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IApyOracle } from "./interfaces/IApyOracle.sol";

// historicalExchangeRate can be thought of as a matrix of past exchange rates by collateral types. With a uint32 type
// storing exchange rates, 8 can be stored in one storage slot. Each day will consume ceil(ILK_COUNT / 8) storage slots.
//
//  look back days  | storage slot  ||                             data
//
//                  |                  256                             128      64     32       0
//                  |               ||  |       |       |       | ilk_n | ilk_3 | ilk_2 | ilk_1 |
//        1         |     n + 0     ||  |       |       |       |       |       |       |       |
//        2         |     n + 1     ||  |       |       |       |       |       |       |       |
//       ...        |    n + ...    ||  |       |       |       |       |       |       |       |
//        n         |     n + n     ||  |       |       |       |       |       |       |       |

uint8 constant APY_PRECISION = 6;
uint8 constant PROVIDER_PRECISION = 18;

uint32 constant LOOK_BACK = 7;
uint256 constant PERIODS = 365 * (10 ** APY_PRECISION) / LOOK_BACK;
uint32 constant ILK_COUNT = 3;
// Seconds in 23.5 hours. This will allow for updates around the same time of day
uint256 constant UPDATE_LOCK_LENGTH = 84_600;

contract ApyOracle is IApyOracle {
    using RoundedMath for uint256;
    using SafeCast for uint256;

    // --- Errors ---

    error InvalidExchangeRate(uint256 ilkIndex);
    error AlreadyUpdated();

    // --- Events ---

    event ApyUpdate(uint256 indexed ilkIndex, uint256 newApy);

    uint32[ILK_COUNT] public apys;

    uint32[ILK_COUNT][LOOK_BACK] public historicalExchangeRates;
    address public immutable address0;
    address public immutable address1;
    address public immutable address2;

    uint32 public currentIndex;
    uint48 public lastUpdated;

    constructor(
        uint32[ILK_COUNT][LOOK_BACK] memory _historicalExchangeRates,
        address _lido,
        address _stader,
        address _swell
    ) {
        historicalExchangeRates = _historicalExchangeRates;

        address0 = _lido;
        address1 = _stader;
        address2 = _swell;

        updateAll();
    }

    function updateAll() public {
        if (lastUpdated + UPDATE_LOCK_LENGTH > block.timestamp) revert AlreadyUpdated();

        uint256 _currentIndex = currentIndex;
        uint32[ILK_COUNT] storage previousExchangeRates = historicalExchangeRates[_currentIndex];

        for (uint256 i = 0; i < ILK_COUNT;) {
            uint32 newExchangeRate = _getExchangeRate(i);
            uint32 previousExchangeRate = previousExchangeRates[i];

            if (newExchangeRate == 0 || newExchangeRate < previousExchangeRate) revert InvalidExchangeRate(i);

            uint256 exchangeRateIncrease = uint256(newExchangeRate - previousExchangeRate).roundedDiv(
                previousExchangeRate, 10 ** (APY_PRECISION + 2)
            );

            uint32 newApy = ((exchangeRateIncrease * PERIODS) / (10 ** APY_PRECISION)).toUint32();
            apys[i] = newApy;
            // Replace previous exchange rates with new exchange rates
            previousExchangeRates[i] = newExchangeRate;

            emit ApyUpdate(i, newApy);

            unchecked {
                ++i;
            }
        }

        // update Apy, history with new exchangeRates, and currentIndex
        currentIndex = (currentIndex + 1) % LOOK_BACK;
        lastUpdated = block.timestamp.toUint48();
    }

    function _getExchangeRate(uint256 ilkIndex) internal view returns (uint32 exchangeRate) {
        uint256 scale = 10 ** (PROVIDER_PRECISION - APY_PRECISION);
        if (ilkIndex == 0) {
            ILidoWstEth lido = ILidoWstEth(address0);
            exchangeRate = (lido.stEthPerToken() / scale).toUint32();
        } else if (ilkIndex == 1) {
            IStaderOracle stader = IStaderOracle(address1);
            (, uint256 totalETHBalance, uint256 totalETHXSupply) = stader.exchangeRate();
            exchangeRate = (_computeStaderExchangeRate(totalETHBalance, totalETHXSupply) / scale).toUint32();
        } else {
            ISwellEth swell = ISwellEth(address2);
            exchangeRate = (swell.swETHToETHRate() / scale).toUint32();
        }
    }

    function _computeStaderExchangeRate(
        uint256 totalETHBalance,
        uint256 totalETHXSupply
    )
        internal
        pure
        returns (uint256)
    {
        if (totalETHBalance == 0 || totalETHXSupply == 0) return (10 ** PROVIDER_PRECISION);

        return totalETHBalance * (10 ** PROVIDER_PRECISION) / totalETHXSupply;
    }
}
