// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { Whitelist } from "../../src/Whitelist.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployWhitelistScript is DeployScript {
    using StdJson for string;

    string configPath = "./deployment-config/03_DeployWhitelist.json";
    string config = vm.readFile(configPath);

    bytes32 lenderRoot = config.readBytes32(".lenderRoot");
    bytes32 borrowerRoot = config.readBytes32(".borrowerRoot");

    bytes32[] borrowerRoots = new bytes32[](1);

    function run() public broadcast returns (Whitelist whitelist) {
        borrowerRoots[0] = borrowerRoot;

        require(borrowerRoots.length == 1, "borrower root length should be one");

        if (deployCreate2) {
            whitelist = new Whitelist{ salt: DEFAULT_SALT }(borrowerRoots, lenderRoot);
        } else {
            whitelist = new Whitelist(borrowerRoots, lenderRoot);
        }
    }
}
