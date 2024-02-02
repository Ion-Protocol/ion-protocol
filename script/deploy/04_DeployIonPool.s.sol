// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { InterestRate } from "../../src/InterestRate.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseScript } from "../Base.s.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployIonPoolScript is BaseScript {
    using StdJson for string;
    using SafeCast for uint256;

    string defaultConfigPath = "./deployment-config/00_Default.json";
    string defaultConfig = vm.readFile(defaultConfigPath);

    address protocol = defaultConfig.readAddress(".protocol");

    string configPath = "./deployment-config/04_DeployIonPool.json";
    string config = vm.readFile(configPath);

    address initialDefaultAdmin = defaultConfig.readAddress(".defaultAdmin");
    address underlying = config.readAddress(".underlying");
    address treasury = config.readAddress(".treasury");
    uint8 decimals = config.readUint(".decimals").toUint8();
    string name = config.readString(".name");
    string symbol = config.readString(".symbol");
    InterestRate interestRateModule = InterestRate(config.readAddress(".interestRateModule"));
    Whitelist whitelist = Whitelist(config.readAddress(".whitelist"));

    function run() public broadcast returns (IonPool ionPool) {
        IonPool ionPoolImpl = new IonPool();

        bytes memory initData = abi.encodeWithSelector(
            IonPool.initialize.selector,
            underlying,
            treasury,
            decimals,
            name,
            symbol,
            initialDefaultAdmin,
            interestRateModule,
            whitelist
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(ionPoolImpl), initialDefaultAdmin, initData);
        ionPool = IonPool(address(proxy));
    }
}
