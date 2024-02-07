// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { IonPool } from "../../src/IonPool.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployInitialGemJoinsScript is DeployScript {
    using StdJson for string;

    string configPath = "./deployment-config/07_DeployInitialGemJoins.json";
    string config = vm.readFile(configPath);

    IonPool ionPool = IonPool(config.readAddress(".ionPool"));

    function run() public broadcast returns (GemJoin gemJoin) {
        require(address(ionPool).code.length > 0, "ionPool address must have code");
        // Test the interface
        ionPool.balanceOf(address(this));
        ionPool.debt();
        ionPool.isOperator(address(this), address(this));

        IERC20 ilkERC20 = IERC20(ilkAddress);
        ilkERC20.balanceOf(address(this));
        ilkERC20.totalSupply();
        ilkERC20.allowance(address(this), address(this));

        gemJoin = new GemJoin(ionPool, ilkERC20, 0, protocol);
        ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(gemJoin));
    }
}
