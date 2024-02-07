// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19 <=0.9.0;

import { Errors } from "../src/Errors.sol";
import { BaseScript } from "./Base.s.sol";

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

abstract contract DeployScript is BaseScript, Errors {
    using StdJson for string;
    using Strings for uint256;

    uint8 constant ILK_INDEX_ZERO = 0;

    string defaultConfigPath = "./deployment-config/00_Default.json";
    string defaultConfig = vm.readFile(defaultConfigPath);

    // default config values
    address initialDefaultAdmin = vm.parseJsonAddress(defaultConfig, ".initialDefaultAdmin");
    address protocol = vm.parseJsonAddress(defaultConfig, ".protocol");
    address ilkAddress = vm.parseJsonAddress(defaultConfig, ".ilkAddress");
    string marketId = defaultConfig.readString(".marketId");
}
