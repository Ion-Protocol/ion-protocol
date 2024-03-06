// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";
import { YieldOracle, LOOK_BACK, ILK_COUNT } from "../../src/YieldOracle.sol";

import { DeployScript } from "../Deploy.s.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployYieldOracleScript is DeployScript {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    string configPath = "./deployment-config/01_DeployYieldOracle.json";
    string config;
    string[] configKeys;
    uint256[] weEthRates;
    uint256[] staderRates;
    uint256[] swellRates;
    address weEthExchangeRateAddress;
    address staderExchangeRateAddress;
    address swellExchangeRateAddress;

    function run() public broadcast returns (YieldOracle yieldOracle) {
        config = vm.readFile(configPath);

        configKeys = vm.parseJsonKeys(config, ".exchangeRateData");

        weEthRates = vm.parseJsonUintArray(config, ".exchangeRateData.weETH.historicalExchangeRates");
        staderRates = vm.parseJsonUintArray(config, ".exchangeRateData.stader.historicalExchangeRates");
        swellRates = vm.parseJsonUintArray(config, ".exchangeRateData.swell.historicalExchangeRates");

        weEthExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.weETH.address");
        staderExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.stader.address");
        swellExchangeRateAddress = vm.parseJsonAddress(config, ".exchangeRateData.swell.address");

        assert(configKeys.length == ILK_COUNT);
        require(initialDefaultAdmin != address(0), "Default admin address is zero");

        // wstETH is replaced with weETH to not break compatibility.

        uint64[ILK_COUNT][LOOK_BACK] memory historicalExchangeRates;

        for (uint256 i = 0; i < LOOK_BACK; i++) {
            uint64 weEthEr = (weEthRates[i]).toUint64();
            uint64 staderEr = (staderRates[i]).toUint64();
            uint64 swellEr = (swellRates[i]).toUint64();

            uint64[ILK_COUNT] memory exchangesRates = [weEthEr, staderEr, swellEr];

            historicalExchangeRates[i] = exchangesRates;
        }

        if (deployCreate2) {
            yieldOracle = new YieldOracle{ salt: DEFAULT_SALT }(
                historicalExchangeRates,
                weEthExchangeRateAddress,
                staderExchangeRateAddress,
                swellExchangeRateAddress,
                initialDefaultAdmin
            );
        } else {
            yieldOracle = new YieldOracle(
                historicalExchangeRates,
                weEthExchangeRateAddress,
                staderExchangeRateAddress,
                swellExchangeRateAddress,
                initialDefaultAdmin
            );
        }
    }

    function configureDeployment() public {
        string[] memory inputs = new string[](3);
        inputs[0] = "bun";
        inputs[1] = "run";
        inputs[2] = "offchain/scrapePastExchangeRates.ts";

        bytes memory res = vm.ffi(inputs);
        vm.writeJson(string(res), configPath);
    }
}
