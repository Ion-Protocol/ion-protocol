// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployIonPoolScript } from "../deploy/04_DeployIonPool.s.sol";
import { Test } from "forge-std/Test.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployIonPoolTest is DeployTestBase, DeployIonPoolScript {

    function checkState(IonPool ionPool) public {

        require(address(ionPool).code.length > 0); 
        require(ionPool.owner() == initialDefaultAdmin); 
        require(ionPool.defaultAdmin() == initialDefaultAdmin); 
        require(address(ionPool.underlying()) == underlying); 
        require(ionPool.treasury() == treasury); 
        require(ionPool.decimals() == 18); 
        require(ionPool.interestRateModule() == address(interestRateModule));
        require(ionPool.whitelist() == address(whitelist)); 
        
        vm.startPrank(initialDefaultAdmin); 
        ionPool.beginDefaultAdminTransfer(protocol); 
        vm.stopPrank(); 

        // warp time past default admin transfer delay 

        vm.startPrank(protocol); 
        ionPool.acceptDefaultAdminTransfer(); 
        vm.stopPrank(); 

        require(ionPool.owner() == protocol); 
        require(ionPool.defaultAdmin() == protocol);  
    }

    function test_PreExecution() public {
        checkState(super.run()); 
    }
}




