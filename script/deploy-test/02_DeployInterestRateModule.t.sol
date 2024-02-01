// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { InterestRate } from "../../src/InterestRate.sol";
import { DeployInterestRateScript } from "../deploy/02_DeployInterestRateModule.s.sol";
import { Test } from "forge-std/Test.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployInterestRateModuleTest is DeployTestBase, DeployInterestRateScript {

    function checkState(InterestRate interestRate) public view {
        console2.log("address(interestRate).code.length: ", address(interestRate).code.length);
        console2.log("address(0).code", address(0).code.length);
        require(address(interestRate).code.length > 0); 
        require(interestRate.COLLATERAL_COUNT() == 3); 
        require(address(interestRate.YIELD_ORACLE()) == address(yieldOracle)); 
        // NOTE: all the interest rate params and unpack configs are internal 
    }

    function test_PreExecution() public {
        checkState(super.run()); 
    }
}




