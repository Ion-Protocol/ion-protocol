// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { InterestRate, IlkData } from "../../src/InterestRate.sol";
import { DeployInterestRateScript } from "../deploy/02_DeployInterestRateModule.s.sol";

contract DeployInterestRateModuleTest is DeployTestBase, DeployInterestRateScript {
    function checkState(InterestRate interestRate) public view {
        assert(address(interestRate).code.length > 0);
        assert(interestRate.COLLATERAL_COUNT() == 1);
        assert(address(interestRate.YIELD_ORACLE()) == address(yieldOracle));

        IlkData memory ilkData = interestRate.unpackCollateralConfig(0);
        assert(ilkData.adjustedProfitMargin == adjustedProfitMargin);
        assert(ilkData.minimumKinkRate == minimumKinkRate);
        assert(ilkData.reserveFactor == reserveFactor);
        assert(ilkData.adjustedBaseRate == adjustedBaseRate);
        assert(ilkData.minimumBaseRate == minimumBaseRate);
        require(ilkData.optimalUtilizationRate == optimalUtilizationRate);
        require(ilkData.distributionFactor == DISTRIBUTION_FACTOR);
        require(ilkData.adjustedAboveKinkSlope == adjustedAboveKinkSlope);
        require(ilkData.minimumAboveKinkSlope == minimumAboveKinkSlope);

        // reasonable extrapolation
    }

    function test_PreExecution() public {
        checkState(super.run());
    }
}
