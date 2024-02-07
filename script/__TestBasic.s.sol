// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "../src/IonPool.sol";
import { IWETH9 } from "../src/interfaces/IWETH9.sol";

import { BaseScript } from "./Base.s.sol";

// TODO: consolidate constants
IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant ADDRESS_1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

// TODO: add to BaseScript
contract Addresses is BaseScript {
    string configPath = "./deployment-config/DeployedAddresses.json";
    string config = vm.readFile(configPath);

    IonPool pool = IonPool(vm.parseJsonAddress(config, ".ionPool"));
}

contract Setup is Addresses {
    function run() public broadcast {
        pool.updateSupplyCap(type(uint256).max);
        pool.updateIlkDebtCeiling(0, type(uint256).max);
        pool.updateIlkDebtCeiling(1, type(uint256).max);
        pool.updateIlkDebtCeiling(2, type(uint256).max);
    }
}

contract Supply is Addresses {
    function run() public broadcastFrom(ADDRESS_1) {
        WETH.deposit{ value: 500 ether }();
        WETH.approve(address(pool), type(uint256).max);
        pool.supply(ADDRESS_1, 500 ether, new bytes32[](0));
    }
}

contract Withdraw is Addresses {
    function run() public broadcastFrom(ADDRESS_1) {
        pool.withdraw(ADDRESS_1, 500 ether);
    }
}
