// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Whitelist } from "../../src/Whitelist.sol";

import { BaseScript } from "../Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployWhitelistScript is BaseScript {
    using StdJson for string;

    string defaultConfigPath = "./deployment-config/00_Default.json";
    string defaultConfig = vm.readFile(defaultConfigPath);

    string configPath = "./deployment-config/03_DeployWhitelist.json";
    string config = vm.readFile(configPath);

    address protocol = vm.parseJsonAddress(defaultConfig, ".protocol");

    bytes32 lenderRoot = config.readBytes32(".lenderRoot");
    bytes32[] borrowerRoots = config.readBytes32Array(".borrowerRoots");
    address[] protocolControlledAddresses = config.readAddressArray(".protocolControlledAddresses");

    bytes32 INACTIVE = keccak256("INACTIVE");

    function run() public broadcast returns (Whitelist whitelist) {
        require(borrowerRoots.length == 1, "borrower root length should be one");
        // TODO: remove
        borrowerRoots.push(INACTIVE);
        borrowerRoots.push(INACTIVE);

        whitelist = new Whitelist(borrowerRoots, lenderRoot);

        for (uint256 i = 0; i < protocolControlledAddresses.length; i++) {
            whitelist.approveProtocolWhitelist(protocolControlledAddresses[i]);
        }

        // initiate Ownable2Step transfer
        whitelist.transferOwnership(protocol);
    }
}
