// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { Whitelist } from "src/Whitelist.sol";
import { InterestRate } from "src/InterestRate.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { BaseScript } from "script/Base.s.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployIonPoolScript is BaseScript {
    using StdJson for string;
    using SafeCast for uint256;

    string configPath = "./deployment-config/04_IonPool.json";
    string config = vm.readFile(configPath);

    function run() public broadcast returns (IonPool ionPool, TransparentUpgradeableProxy proxy) {
        IonPool ionPoolImpl = new IonPool();

        address underlying = config.readAddress(".underlying");
        address treasury = config.readAddress(".treasury");
        uint8 decimals = config.readUint(".decimals").toUint8();
        string memory name = config.readString(".name");
        string memory symbol = config.readString(".symbol");
        address initialDefaultAdmin = config.readAddress(".initialDefaultAdmin");
        InterestRate interestRateModule = InterestRate(config.readAddress(".interestRateModule"));
        Whitelist whitelist = Whitelist(config.readAddress(".whitelist"));

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

        proxy = new TransparentUpgradeableProxy(address(ionPoolImpl), initialDefaultAdmin, initData);
        ionPool = IonPool(address(proxy));
    }
}
