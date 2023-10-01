// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ILidoWstETH, IStaderOracle, ISwellETH } from "../../src/interfaces/IProviderExchangeRate.sol";
import { RoundedMath } from "../../src/math/RoundedMath.sol";
import { ApyOracle, _LOOK_BACK, _PROVIDER_PRECISION, _APY_PRECISION, _ILKS, _PERIODS } from "src/APYOracle.sol";

uint256 constant LOOK_BACK = _LOOK_BACK;
uint256 constant ILKS = _ILKS;
uint256 constant APY_PRECISION = _APY_PRECISION;
uint256 constant PROVIDER_PRECISION = _PROVIDER_PRECISION;
uint256 constant PERIODS = _PERIODS;
uint256 constant DECIMAL_FACTOR = 10 ** (_PROVIDER_PRECISION - _APY_PRECISION);

contract ApyOracleForkTest is Test {
    using RoundedMath for uint256;
    using SafeCast for uint256;

    uint256 public timestamp;
    uint256 public mainnetFork;
    uint256 public startTime;
    address public immutable lidoAddress = vm.envAddress("LIDO_CONTRACT_ADDRESS");
    address public immutable staderAddress = vm.envAddress("STADER_CONTRACT_ADDRESS");
    address public immutable swellAddress = vm.envAddress("SWELL_CONTRACT_ADDRESS");
    string public mainnetRPC;
    ApyOracle public oracle;

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

    function setUp() public {
        // set simulation period here
        uint256 simulationPeriod = 15 days;
        assert(simulationPeriod > LOOK_BACK * 1 days);
        
        mainnetRPC = vm.envString("MAINNET_RPC_URL");
        mainnetFork = vm.createFork(mainnetRPC);
        console.log(block.timestamp);
        timestamp = block.timestamp;
        startTime = block.timestamp - (simulationPeriod * 1 days);

        uint256[LOOK_BACK] memory historicalExchangeRates = initHistoryExchangeRates();
        oracle = new ApyOracle(historicalExchangeRates, lidoAddress, staderAddress, swellAddress);
    }


    function initHistoryExchangeRates() public returns (uint256[LOOK_BACK] memory) { 
        // set custome values for testing purposes
        uint256[LOOK_BACK] memory historicalExchangeRates;
        // set custome values for testing purposes
        uint256 currentTime = startTime;
        uint256 index;
        while (currentTime < startTime + (LOOK_BACK * 1 days)) {
            // create a fork at current time block stamp and get the exchange rates
            uint256 fork = vm.createFork(mainnetRPC, currentTime);
            vm.selectFork(fork);
            // get the exchange rates from the fork
            uint32 lidoExchangeRate = (ILidoWstETH(lidoAddress).stEthPerToken() / DECIMAL_FACTOR).toUint32();
            (, uint256 totalETHBalance, uint256 totalETHXSupply)  = IStaderOracle(staderAddress).exchangeRate();
            uint32 staderExchangeRate = (_computeStaderExchangeRate(totalETHBalance, totalETHXSupply) / DECIMAL_FACTOR).toUint32();
            uint32 swellExchangeRate = (ISwellETH(swellAddress).swETHToETHRate() / DECIMAL_FACTOR).toUint32();
            // set up the array of exchange rates
            uint32[ILKS] memory extractedRates;
            extractedRates[0] = lidoExchangeRate;
            extractedRates[1] = staderExchangeRate;
            extractedRates[2] = swellExchangeRate;
            // bitpack the exchange rates
            uint256 rates;
            for (uint256 i = 0; i < ILKS; i++) {
                rates |= uint256(extractedRates[i]) << (i * 32);
            }
            // add to the exchange rates array and increment time
            historicalExchangeRates[index] = rates;
            currentTime += 1 days;
            index += 1;
        }
        return historicalExchangeRates;
    }

    function testSimulation() public {
        // set up time for simulation to be one block after historical exchange rates
        uint256 currentTime = startTime + (LOOK_BACK * 1 days) + 1;
        vm.selectFork(mainnetFork);
        uint256 finalTimestamp = block.timestamp;        
        while (currentTime < finalTimestamp) {
            uint256 fork = vm.createFork(mainnetRPC, currentTime);
            vm.selectFork(fork);
            // extract newest exchange rates from fork and calculate expected APR
            uint32 lidoExchangeRate = (ILidoWstETH(lidoAddress).stEthPerToken() / DECIMAL_FACTOR).toUint32();
            (, uint256 totalETHBalance, uint256 totalETHXSupply)  = IStaderOracle(staderAddress).exchangeRate();
            uint32 staderExchangeRate = (_computeStaderExchangeRate(totalETHBalance, totalETHXSupply) / DECIMAL_FACTOR).toUint32();
            uint32 swellExchangeRate = (ISwellETH(swellAddress).swETHToETHRate() / DECIMAL_FACTOR).toUint32();
            // bitpack the expected APRs
            uint32[ILKS] memory extractedRates;
            extractedRates[0] = lidoExchangeRate;
            extractedRates[1] = staderExchangeRate;
            extractedRates[2] = swellExchangeRate;
            uint256 expectedAPR;
            for (uint32 i = 0; i < ILKS; i++) {
                uint32 ilkExchangeRate = oracle.getHistoryByProvider(oracle.currentIndex(), i);
                uint256 periodictInterest = uint256(extractedRates[i] - ilkExchangeRate).roundedDiv(
                    uint256(ilkExchangeRate), 10 ** (APY_PRECISION + 2)
                );
                uint256 expectedIlkAPR = (periodictInterest * PERIODS) / 10 ** APY_PRECISION;
                expectedAPR |= expectedIlkAPR << (i * 32);
            }
            // update exchange rates and APR on oracle
            oracle.updateAll();
            // compate expected APR with oracle APR
            uint256 oracleAPR = oracle.getAll();
            assertEq(oracleAPR, expectedAPR);
            // increment time
            currentTime += 1 days;
        }

    }
}