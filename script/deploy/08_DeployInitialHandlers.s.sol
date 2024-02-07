// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { MAINNET_WSTETH_WETH_UNISWAP } from "../../src/Constants.sol";
import { DeployScript } from "../Deploy.s.sol";
import { IonPool } from "../../src/IonPool.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { IonHandlerBase } from "../../src/flash/handlers/base/IonHandlerBase.sol";
import { WeEthHandler } from "../../src/flash/handlers/WeEthHandler.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

// NOTE: Different handlers will have different constructor parameters.
// This script should be reconfigured on each handler deployment.
contract DeployInitialHandlersScript is DeployScript {
    using StdJson for string;

    string configPath = "./deployment-config/08_DeployInitialHandlers.json";
    string config = vm.readFile(configPath);

    function run() public broadcast returns (IonHandlerBase handler) {
        IonPool ionPool = IonPool(config.readAddress(".ionPool"));
        GemJoin gemJoin = GemJoin(config.readAddress(".gemJoin"));
        Whitelist whitelist = Whitelist(config.readAddress(".whitelist"));

        _validateInterface(ionPool);
        _validateInterface(gemJoin);
        _validateInterface(whitelist);

        handler = new WeEthHandler(ILK_INDEX_ZERO, ionPool, gemJoin, whitelist, MAINNET_WSTETH_WETH_UNISWAP);

        // whitelist handler address for protocol controlled addresses
        whitelist.approveProtocolWhitelist(address(handler));
    }
}
