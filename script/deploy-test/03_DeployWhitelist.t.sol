// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;
import { DeployTestBase } from "./00_DeployTestBase.t.sol";
import { DeployWhitelistScript } from "../deploy/03_DeployWhitelist.s.sol";
import { Whitelist } from "../../src/Whitelist.sol"; 
import { Test } from "forge-std/Test.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployWhitelistTest is DeployTestBase, DeployWhitelistScript {

    function checkState(Whitelist whitelist) public {
        require(address(whitelist).code.length > 0); 
        require(whitelist.lendersRoot() == lenderRoot); 
        require(whitelist.borrowersRoot(0) == borrowerRoots[0]);
        require(whitelist.borrowersRoot(1) == INACTIVE);  
        require(whitelist.borrowersRoot(2) == INACTIVE);  

        for (uint256 i = 0; i < protocolControlledAddresses.length; i++) {
            require(whitelist.protocolWhitelist(protocolControlledAddresses[i])); 
        }

        require(whitelist.pendingOwner() == protocol); 
        
        vm.startPrank(protocol); 
        whitelist.acceptOwnership(); 
        vm.stopPrank(); 

        require(whitelist.owner() == protocol); 
        require(whitelist.pendingOwner() == address(0)); 
    }

    function test_PreExecution() public {
        checkState(super.run()); 
    }
}




