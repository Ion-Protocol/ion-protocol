// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { BaseScript } from "./Base.s.sol";
import { console2 } from "forge-std/Script.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { YieldOracle, LOOK_BACK, PROVIDER_PRECISION, APY_PRECISION, ILK_COUNT } from "src/YieldOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployYieldOracleScript is BaseScript {
    using RoundedMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    string configPath = "./deployment-config/YieldOracle.json";
    string config = vm.readFile(configPath);

    uint256 internal constant SCALE = 10 ** (PROVIDER_PRECISION - APY_PRECISION);

    function run() public broadcast returns (YieldOracle apyOracle) {
        string[] memory configKeys = vm.parseJsonKeys(config, ".exchangeRateData");
        assert(configKeys.length == ILK_COUNT);

        uint256[] memory lidoRates = vm.parseJsonUintArray(config, ".exchangeRateData.lido.historicalExchangeRates");
        uint256[] memory staderRates = vm.parseJsonUintArray(config, ".exchangeRateData.stader.historicalExchangeRates");
        uint256[] memory swellRates = vm.parseJsonUintArray(config, ".exchangeRateData.swell.historicalExchangeRates");

        address lidoExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.lido.address");
        address staderExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.stader.address");
        address swellExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.swell.address");

        uint64[ILK_COUNT][LOOK_BACK] memory historicalExchangeRates;

        for (uint256 i = 0; i < LOOK_BACK; i++) {
            uint64 lidoEr = (lidoRates[i] / SCALE).toUint32();
            uint64 staderEr = (staderRates[i] / SCALE).toUint32();
            uint64 swellEr = (swellRates[i] / SCALE).toUint32();

            uint64[ILK_COUNT] memory exchangesRates = [lidoEr, staderEr, swellEr];

            historicalExchangeRates[i] = exchangesRates;
        }

        apyOracle =
        new YieldOracle(historicalExchangeRates, lidoExchangeRateAddress, staderExchangeRateAddress, swellExchangeRateAddress);
    }

    function configureDeployment() external {
        string[] memory inputs = new string[](3);
        inputs[0] = "bun";
        inputs[1] = "run";
        inputs[2] = "offchain/scrapePastExchangeRates.ts";

        bytes memory res = vm.ffi(inputs);

        if (!vm.exists(configPath)) {
            vm.writeFile(configPath, string(""));
        }
        vm.writeJson(string(res), configPath);
    }
}
