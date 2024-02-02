// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { IonHandlerBase } from "../../src/flash/handlers/base/IonHandlerBase.sol";
import { BaseScript } from "../Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployInitialHandlersScript is BaseScript {
    using StdJson for string;

    string configPath = "./deployment-config/08_DeployInitialHandlers.json";
    string config = vm.readFile(configPath);

    function run() public broadcast returns (IonHandlerBase flashHandler) {
        IonPool ionPool = IonPool(config.readAddress(".ionPool"));
        GemJoin gemJoin = GemJoin(config.readAddress(".gemJoin"));
        Whitelist whitelist = Whitelist(config.readAddress(".whitelist"));

        require(address(ionPool) != address(0), "ionPool address cannot be zero");
        require(address(gemJoin) != address(0), "gemJoin address cannot be zero");
        require(address(whitelist) != address(0), "whitelist address cannot be zero");

        // TODO: Deploy new UniswapDirectMintHandler for weETH/wstETH market
    }
}
