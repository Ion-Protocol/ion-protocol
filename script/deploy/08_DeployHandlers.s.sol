// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { MAINNET_WSTETH_WETH_UNISWAP, EZETH_WETH_BALANCER_POOL_ID } from "../../src/Constants.sol";
import { DeployScript } from "../Deploy.s.sol";
import { IonPool } from "../../src/IonPool.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { IonHandlerBase } from "../../src/flash/IonHandlerBase.sol";
import { EzEthWethHandler } from "./../../src/flash/lrt/EzEthWethHandler.sol";
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
            handler = new EzEthWethHandler{ salt: DEFAULT_SALT }(
                ILK_INDEX_ZERO, ionPool, gemJoin, whitelist, MAINNET_WSTETH_WETH_UNISWAP, EZETH_WETH_BALANCER_POOL_ID
            );
        } else {
            handler = new EzEthWethHandler{ salt: DEFAULT_SALT }(
                ILK_INDEX_ZERO, ionPool, gemJoin, whitelist, MAINNET_WSTETH_WETH_UNISWAP, EZETH_WETH_BALANCER_POOL_ID
            );
        }
    }
}
