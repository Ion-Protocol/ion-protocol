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
        IERC20 ilkERC20 = IERC20(ilkAddress);

        _validateInterface(ionPool);
        _validateInterface(ilkERC20);

        gemJoin = new GemJoin(ionPool, ilkERC20, 0, protocol);
        ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(gemJoin));
    }
}
