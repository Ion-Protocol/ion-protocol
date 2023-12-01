// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Whitelist } from "../src/Whitelist.sol";

import { BaseScript } from "./Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployWhitelistScript is BaseScript {
    using StdJson for string;

    string configPath = "./deployment-config/03_Whitelist.json";
    string config = vm.readFile(configPath);

    function run() public broadcast returns (Whitelist whitelist) {
        bytes32 lenderRoot = config.readBytes32(".lenderRoot");
        bytes32[] memory borrowerRoots = config.readBytes32Array(".borrowerRoots");

        whitelist = new Whitelist(borrowerRoots, lenderRoot);
    }
}
