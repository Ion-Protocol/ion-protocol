// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { IonZapper } from "src/periphery/IonZapper.sol";
import { IWETH9 } from "src/interfaces/IWETH9.sol";
import { BaseScript } from "script/Base.s.sol";
import { console2 } from "forge-std/console2.sol";

// TODO: consolidate constants
IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant ADDRESS_1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

// TODO: add to BaseScript
contract Addresses is BaseScript {
    string configPath = "./deployment-config/DeployedAddresses.json";
    string config = vm.readFile(configPath);

    IonPool pool = IonPool(vm.parseJsonAddress(config, ".ionPool"));
    IonZapper ionZapper = IonZapper(vm.parseJsonAddress(config, ".ionZapper"));
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
        // pool.withdraw(ADDRESS_1, 500 ether, new bytes32[](0));
    }
}

contract ZapSupply is Addresses {
    function run() public broadcastFrom(ADDRESS_1) {
        ionZapper.zapSupply{ value: 2 ether }(new bytes32[](0));
    }
}

contract View is Addresses {
    function run() public view {
        address user = broadcaster;
        console2.log("user: ", user);

        // console2.log("supply cap: ", pool.supplyCap());
        (uint256 collateral0, uint256 normalizedDebt0) = pool.vault(0, user);
        (uint256 collateral1, uint256 normalizedDebt1) = pool.vault(1, user);
        (uint256 collateral2, uint256 normalizedDebt2) = pool.vault(2, user);

        console2.log("weth: ", pool.weth());
        console2.log("rewardToken Balance: ", pool.balanceOf(user));

        console2.log("collateral0: ", collateral0);
        console2.log("normalizedDebt0: ", normalizedDebt0);
        console2.log("collateral1: ", collateral1);
        console2.log("normalizedDebt1: ", normalizedDebt1);
        console2.log("collateral2: ", collateral2);
        console2.log("normalizedDebt2: ", normalizedDebt2);
    }
}
