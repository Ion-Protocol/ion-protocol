// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BASE_WETH, BASE_EZETH_WETH_AERODROME } from "../../src/Constants.sol";
import { DeployScript } from "../Deploy.s.sol";
import { IonPool } from "../../src/IonPool.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { IonHandlerBase } from "../../src/flash/IonHandlerBase.sol";
import { BaseEzEthWethHandler } from "./../../src/flash/lrt/base/BaseEzEthWethHandler.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

// NOTE: Different handlers will have different constructor parameters.
// NOTE: THIS SCRIPT MUST BE reconfigured on each handler deployment.
contract DeployHandlersScript is DeployScript {
    using StdJson for string;

    string configPath = "./deployment-config/08_DeployHandlers.json";
    string config = vm.readFile(configPath);

    IonPool ionPool = IonPool(config.readAddress(".ionPool"));
    GemJoin gemJoin = GemJoin(config.readAddress(".gemJoin"));
    Whitelist whitelist = Whitelist(config.readAddress(".whitelist"));

    function run() public broadcast returns (IonHandlerBase handler) {
        _validateInterface(gemJoin);
        _validateInterface(whitelist);
        _validateInterfaceIonPool(ionPool);

        if (deployCreate2) {
            handler = new BaseEzEthWethHandler{ salt: DEFAULT_SALT }(
                ILK_INDEX_ZERO, ionPool, gemJoin, whitelist, BASE_EZETH_WETH_AERODROME, false, BASE_WETH
            );
        } else {
            handler = new BaseEzEthWethHandler(
                ILK_INDEX_ZERO, ionPool, gemJoin, whitelist, BASE_EZETH_WETH_AERODROME, false, BASE_WETH
            );
        }
    }
}
