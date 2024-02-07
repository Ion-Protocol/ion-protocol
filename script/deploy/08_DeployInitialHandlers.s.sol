// SPDX-License-Identifier: UNLICENSED
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

        require(address(ionPool).code.length > 0, "ionPool address must have code");
        // Test the interface
        ionPool.balanceOf(address(this));
        ionPool.debt();
        ionPool.isOperator(address(this), address(this));

        require(address(gemJoin).code.length > 0, "gemJoin address must have code");
        // Test the interface
        gemJoin.totalGem();

        require(address(whitelist).code.length > 0, "whitelist address must have code");
        // Test interface
        whitelist.lendersRoot();
        whitelist.borrowersRoot(0);

        handler = new WeEthHandler(ILK_INDEX_ZERO, ionPool, gemJoin, whitelist, MAINNET_WSTETH_WETH_UNISWAP);

        // whitelist handler address for protocol controlled addresses
        whitelist.approveProtocolWhitelist(address(handler));
    }
}
