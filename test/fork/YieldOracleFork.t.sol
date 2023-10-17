// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { stdJson as StdJson } from "forge-std/stdJson.sol";

import { ILidoWstEth, IStaderOracle, ISwellEth } from "../../src/interfaces/OracleInterfaces.sol";
import { RoundedMath } from "../../src/math/RoundedMath.sol";
import { YieldOracle, LOOK_BACK, PROVIDER_PRECISION, APY_PRECISION, ILK_COUNT, PERIODS } from "src/YieldOracle.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract YieldOracleExposed is YieldOracle {
    constructor(
        uint64[ILK_COUNT][LOOK_BACK] memory _historicalExchangeRates,
        address _lido,
        address _stader,
        address _swell
    )
        YieldOracle(_historicalExchangeRates, _lido, _stader, _swell)
    { }

    function getFullApysArray() external view returns (uint32[ILK_COUNT] memory) {
        return apys;
    }

    function getFullHistoricalExchangesRatesArray() external view returns (uint64[ILK_COUNT][LOOK_BACK] memory) {
        return historicalExchangeRates;
    }

    function historicalExchangeRatesByIndex(uint256 currentIndex) external view returns (uint64[ILK_COUNT] memory) {
        return historicalExchangeRates[currentIndex];
    }
}

contract YieldOracle_ForkTest is Test {
    using RoundedMath for uint256;
    using SafeCast for uint256;
    using Strings for *;

    uint256 internal constant SCALE = 10 ** (PROVIDER_PRECISION - APY_PRECISION);
    uint256 internal constant DAYS_TO_GO_BACK = 10;

    YieldOracleExposed public apyOracle;
    // Historical blocks at which oracle would have been updateable, assuming the oracle was launched `DAYS_TO_GO_BACK`
    // days ago
    uint256[] blockNumbersToRollTo;

    uint64[ILK_COUNT][] apysHistory;
    uint64[ILK_COUNT][LOOK_BACK][] historicalExchangeRatesHistory;

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

    // We go back a certain amount of days and pretend the oracle was being
    // launched that many days ago. Then move the days forward until the current
    // day is reached. We run tests on these changes to make sure the expected
    // behavior takes place.
    function setUp() public {
        string[] memory inputs = new string[](5);
        vm.setEnv("CHAIN_ID", "1");
        inputs[0] = "bun";
        inputs[1] = "run";
        inputs[2] = "offchain/scrapePastExchangeRates.ts";
        inputs[3] = DAYS_TO_GO_BACK.toString();

        string memory config = string(vm.ffi(inputs));

        uint256[] memory lidoRates = vm.parseJsonUintArray(config, ".exchangeRateData.lido.historicalExchangeRates");
        uint256[] memory staderRates = vm.parseJsonUintArray(config, ".exchangeRateData.stader.historicalExchangeRates");
        uint256[] memory swellRates = vm.parseJsonUintArray(config, ".exchangeRateData.swell.historicalExchangeRates");

        address lidoExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.lido.address");
        address staderExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.stader.address");
        address swellExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.swell.address");

        uint64[ILK_COUNT][LOOK_BACK] memory historicalExchangeRates;

        for (uint256 i = 0; i < LOOK_BACK; i++) {
            uint64 lidoExchangeRate = (lidoRates[i]).toUint64();
            uint64 staderExchangeRate = (staderRates[i]).toUint64();
            uint64 swellExchangeRate = (swellRates[i]).toUint64();

            uint64[ILK_COUNT] memory exchangesRates = [lidoExchangeRate, staderExchangeRate, swellExchangeRate];

            historicalExchangeRates[i] = exchangesRates;
        }

        // Equivalent of `.dailyBlockData[${LOOK_BACK - 1}].blockNumber
        uint256 blockNumberAtLastUpdate =
            vm.parseJsonUint(config, string.concat(".dailyBlockData[", (LOOK_BACK - 1).toString(), "].blockNumber"));
        blockNumbersToRollTo = vm.parseJsonUintArray(config, ".nextDaysBlockData.blockNumbers");

        uint256 mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"), blockNumberAtLastUpdate + 1);
        vm.selectFork(mainnetFork);

        apyOracle =
        new YieldOracleExposed(historicalExchangeRates, lidoExchangeRateAddress, staderExchangeRateAddress, swellExchangeRateAddress);
        vm.makePersistent(address(apyOracle));

        apysHistory.push(apyOracle.getFullApysArray());
        historicalExchangeRatesHistory.push(apyOracle.getFullHistoricalExchangesRatesArray());
    }

    function testFork_apyOracleUpdatesWithRealData() public {
        for (uint256 i = 0; i < blockNumbersToRollTo.length; i++) {
            vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), blockNumbersToRollTo[i]);
            uint64 currentIndex = apyOracle.currentIndex();
            uint64[ILK_COUNT] memory ratesToUpdate = apyOracle.historicalExchangeRatesByIndex(currentIndex);

            apyOracle.updateAll();

            uint64[ILK_COUNT] memory updatedRate = apyOracle.historicalExchangeRatesByIndex(currentIndex);

            // Verify that all new rates are higher than the old rates
            for (uint256 j = 0; j < ILK_COUNT; j++) {
                assertGe(updatedRate[j], ratesToUpdate[j]);
            }

            apysHistory.push(apyOracle.getFullApysArray());
            historicalExchangeRatesHistory.push(apyOracle.getFullHistoricalExchangesRatesArray());
        }

        // _printState();
    }

    function _printState() internal view {
        for (uint256 i = 0; i < apysHistory.length; i++) {
            // Construct apy and historicalExchangeRates this point in time
            string memory apyState;
            for (uint256 j = 0; j < apysHistory[i].length; j++) {
                if (j == apysHistory[i].length - 1) {
                    apyState = string.concat(apyState, apysHistory[i][j].toString());
                } else {
                    apyState = (string.concat(apyState, apysHistory[i][j].toString(), ", "));
                }
            }

            console.log("HISTORICAL EXHCNAGE RATES");
            console.log("");
            for (uint256 j = 0; j < historicalExchangeRatesHistory[i].length; j++) {
                string memory historicalExchangeRatesState = string.concat("Day ", j.toString(), ": ");
                for (uint256 k = 0; k < historicalExchangeRatesHistory[i][j].length; k++) {
                    if (k == historicalExchangeRatesHistory[i][j].length - 1) {
                        historicalExchangeRatesState = string.concat(
                            historicalExchangeRatesState, historicalExchangeRatesHistory[i][j][k].toString()
                        );
                    } else {
                        historicalExchangeRatesState = string.concat(
                            historicalExchangeRatesState, historicalExchangeRatesHistory[i][j][k].toString(), ", "
                        );
                    }
                }
                console2.log(historicalExchangeRatesState);
            }

            console.log("");
            console.log("APYS");
            console2.log(apyState);
            console.log("");
            console.log("----------");
            console.log("");
        }
    }
}
