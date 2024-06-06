// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { InterestRate, IlkData } from "../../src/InterestRate.sol";
import { YieldOracle } from "../../src/YieldOracle.sol";
import { LibString } from "solady/src/utils/LibString.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { console2 } from "forge-std/console2.sol";

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

    YieldOracle yieldOracle = YieldOracle(config.readAddress(".yieldOracleAddress"));

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
        require(optimalUtilizationRate <= 1e4, "optimalUtilizationRate too high");

        _validateInterface(yieldOracle);

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
        if (deployCreate2) {
            interestRateModule = new InterestRate{ salt: DEFAULT_SALT }(ilkDataList, yieldOracle);
        } else {
            interestRateModule = new InterestRate(ilkDataList, yieldOracle);
        }

        (uint256 zeroUtilRate,) = interestRateModule.calculateInterestRate(0, 0, 100e18);
        zeroUtilRate += 1e27;

        uint256 annualZeroUtilRate = _rpow(zeroUtilRate, 31_536_000, 1e27);

        uint256 optimalUtilTotalIlkDebt = uint256(optimalUtilizationRate) * 100e18 / 1e4 * 1e27;
        (uint256 optimalUtilRate,) = interestRateModule.calculateInterestRate(0, 90e45, 100e18);
        optimalUtilRate += 1e27;

        uint256 annualOptimalUtilRate = _rpow(optimalUtilRate, 31_536_000, 1e27);

        // Get the borrow rate at a 100% utilization rate
        (uint256 maxUtilRate,) = interestRateModule.calculateInterestRate(0, 100e45, 100e18);
        maxUtilRate += 1e27;

        uint256 annualMaxUtilRate = _rpow(maxUtilRate, 31_536_000, 1e27);

        console2.log("annual zero utilization rate: ", annualZeroUtilRate);
        console2.log("annual optimal utilization rate: ", annualOptimalUtilRate);
        console2.log("annual max utilization rate: ", annualMaxUtilRate);

        require(annualZeroUtilRate < 1.1e27, "Annual zero utilization rate too high");
        require(annualOptimalUtilRate < 1.2e27, "Annual optimal utilization rate too high");
        require(annualMaxUtilRate < 1.4e27, "Annual max utilization rate too high");
    }

    function _rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := b }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := b }
                default { z := x }
                let half := div(b, 2) // for rounding.
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, b)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, b)
                    }
                }
            }
        }
    }
}
