// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Errors } from "../../src/Errors.sol";
import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";
import { YieldOracle, LOOK_BACK, PROVIDER_PRECISION, APY_PRECISION, ILK_COUNT } from "../../src/YieldOracle.sol";

import { BaseScript } from "../Base.s.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";
import { console2 } from "forge-std/Script.sol";

contract DeployYieldOracleScript is BaseScript, Errors {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    string defaultConfigPath = "./deployment-config/00_Default.json";
    string defaultConfig = vm.readFile(defaultConfigPath);

    string configPath = "./deployment-config/01_DeployYieldOracle.json";
    string config = vm.readFile(configPath);

    string[] configKeys = vm.parseJsonKeys(config, ".exchangeRateData");
    address defaultAdminAddress = vm.parseJsonAddress(defaultConfig, ".defaultAdmin");

    uint256[] weEthRates = vm.parseJsonUintArray(config, ".exchangeRateData.weETH.historicalExchangeRates");
    uint256[] staderRates = vm.parseJsonUintArray(config, ".exchangeRateData.stader.historicalExchangeRates");
    uint256[] swellRates = vm.parseJsonUintArray(config, ".exchangeRateData.swell.historicalExchangeRates");

    address weEthExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.weETH.address");
    address staderExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.stader.address");
    address swellExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.swell.address");

    function run() public broadcast returns (YieldOracle yieldOracle) {
        assert(configKeys.length == ILK_COUNT);
        require(defaultAdminAddress != address(0), "Default admin address is zero");

        // wstETH is replaced with weETH to not break compatibility.

        uint64[ILK_COUNT][LOOK_BACK] memory historicalExchangeRates;

        for (uint256 i = 0; i < LOOK_BACK; i++) {
            uint64 weEthEr = (weEthRates[i]).toUint64();
            uint64 staderEr = (staderRates[i]).toUint64();
            uint64 swellEr = (swellRates[i]).toUint64();

            uint64[ILK_COUNT] memory exchangesRates = [weEthEr, staderEr, swellEr];

            historicalExchangeRates[i] = exchangesRates;
        }

        yieldOracle = new YieldOracle(
            historicalExchangeRates,
            weEthExchangeRateAddress,
            staderExchangeRateAddress,
            swellExchangeRateAddress,
            defaultAdminAddress
        );
    }

    function configureDeployment() public {
        string[] memory inputs = new string[](4);
        inputs[0] = "CHAIN_ID=1";
        inputs[1] = "bun";
        inputs[2] = "run";
        inputs[3] = "offchain/scrapePastExchangeRates.ts";

        bytes memory res = vm.ffi(inputs);

        if (!vm.exists(configPath)) {
            vm.writeFile(configPath, string(""));
        }
        vm.writeJson(string(res), configPath);
    }
}
