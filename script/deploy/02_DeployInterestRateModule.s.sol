// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { InterestRate, IlkData } from "../../src/InterestRate.sol";
import { IYieldOracle } from "../../src/interfaces/IYieldOracle.sol";
import { LibString } from "solady/src/utils/LibString.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

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

contract DeployInterestRateScript is DeployScript {
    using SafeCast for *;
    using StdJson for string;
    using LibString for string;
    using LibString for uint256;

    string configPath = "./deployment-config/02_DeployInterestRateModule.json";
    string config = vm.readFile(configPath);

    address yieldOracleAddress = config.readAddress(".yieldOracleAddress");
    IYieldOracle yieldOracle = IYieldOracle(yieldOracleAddress);

    uint16 constant DISTRIBUTION_FACTOR = 10_000; // should always be 1, 100%

    uint96 adjustedProfitMargin = config.readUint(".ilkData.adjustedProfitMargin").toUint96();
    uint96 minimumKinkRate = config.readUint(".ilkData.minimumKinkRate").toUint96();
    uint16 reserveFactor = config.readUint(".ilkData.reserveFactor").toUint16();
    uint96 adjustedBaseRate = config.readUint(".ilkData.adjustedBaseRate").toUint96();
    uint96 minimumBaseRate = config.readUint(".ilkData.minimumBaseRate").toUint96();
    uint16 optimalUtilizationRate = config.readUint(".ilkData.optimalUtilizationRate").toUint16();
    uint96 adjustedAboveKinkSlope = config.readUint(".ilkData.adjustedAboveKinkSlope").toUint96();
    uint96 minimumAboveKinkSlope = config.readUint(".ilkData.minimumAboveKinkSlope").toUint96();

    function run() public broadcast returns (InterestRate interestRateModule) {
        require(yieldOracleAddress.code.length > 0, "No code at YieldOracle address");
        yieldOracle.apys(0); // Test the function works

        IlkData memory ilkData;
        ilkData.adjustedProfitMargin = adjustedProfitMargin;
        ilkData.minimumKinkRate = minimumKinkRate;
        ilkData.reserveFactor = reserveFactor;
        ilkData.adjustedBaseRate = adjustedBaseRate;
        ilkData.minimumBaseRate = minimumBaseRate;
        ilkData.optimalUtilizationRate = optimalUtilizationRate;
        ilkData.distributionFactor = DISTRIBUTION_FACTOR;
        ilkData.adjustedAboveKinkSlope = adjustedAboveKinkSlope;
        ilkData.minimumAboveKinkSlope = minimumAboveKinkSlope;

        IlkData[] memory ilkDataList = new IlkData[](1);
        ilkDataList[0] = ilkData;

        // If the ilks array is expanded beyond length one via calling initializeIlk() more than once,
        // all _accrueInterest() would revert as interest rate config only exists for ilkIndex 0.
        // TODO: When calling initializeIlk(), always verify that the length is still zero
        interestRateModule = new InterestRate(ilkDataList, yieldOracle);
    }
}
