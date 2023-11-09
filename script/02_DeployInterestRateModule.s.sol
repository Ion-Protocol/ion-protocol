// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { InterestRate, IlkData } from "src/InterestRate.sol";
import { IYieldOracle } from "src/interfaces/IYieldOracle.sol";

import { LibString } from "solady/src/utils/LibString.sol";

import { BaseScript } from "script/Base.s.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

uint256 constant ILK_COUNT = 3;

// struct IlkData {
//     // Word 1
//     uint96 adjustedProfitMargin; // 27 decimals
//     uint96 minimumKinkRate; // 27 decimals

//     // Word 2
//     uint16 reserveFactor; // 4 decimals
//     uint96 adjustedBaseRate; // 27 decimals
//     uint96 minimumBaseRate; // 27 decimals
//     uint16 optimalUtilizationRate; // 4 decimals
//     uint16 distributionFactor; // 4 decimals

//     // Word 3
//     uint96 adjustedAboveKinkSlope; // 27 decimals
//     uint96 minimumAboveKinkSlope; // 27 decimals
// }

contract DeployInterestRateScript is BaseScript {
    using SafeCast for *;
    using StdJson for string;
    using LibString for string;
    using LibString for uint256;

    string configPath = "./deployment-config/02_InterestRate.json";
    string config = vm.readFile(configPath);

    function run() public broadcast returns (InterestRate interestRateModule) {
        IlkData[] memory ilkDataList = new IlkData[](ILK_COUNT);
        for (uint256 i = 0; i < ILK_COUNT; i++) {
            IlkData memory ilkData;
            ilkData.adjustedProfitMargin =
                config.readUint(string.concat(".", i.toString(), ".ilkData.adjustedProfitMargin")).toUint96();
            ilkData.minimumKinkRate =
                config.readUint(string.concat(".", i.toString(), ".ilkData.minimumKinkRate")).toUint96();

            ilkData.reserveFactor =
                config.readUint(string.concat(".", i.toString(), ".ilkData.reserveFactor")).toUint16();
            ilkData.adjustedBaseRate =
                config.readUint(string.concat(".", i.toString(), ".ilkData.adjustedBaseRate")).toUint96();
            ilkData.minimumBaseRate =
                config.readUint(string.concat(".", i.toString(), ".ilkData.minimumBaseRate")).toUint96();
            ilkData.optimalUtilizationRate =
                config.readUint(string.concat(".", i.toString(), ".ilkData.optimalUtilizationRate")).toUint16();
            ilkData.distributionFactor =
                config.readUint(string.concat(".", i.toString(), ".ilkData.distributionFactor")).toUint16();

            ilkData.adjustedAboveKinkSlope =
                config.readUint(string.concat(".", i.toString(), ".ilkData.adjustedAboveKinkSlope")).toUint96();
            ilkData.minimumAboveKinkSlope =
                config.readUint(string.concat(".", i.toString(), ".ilkData.minimumAboveKinkSlope")).toUint96();

            ilkDataList[i] = ilkData;
        }

        IYieldOracle yieldOracle = IYieldOracle(config.readAddress(".YieldOracleAddress"));

        interestRateModule = new InterestRate(ilkDataList, yieldOracle);
    }
}
