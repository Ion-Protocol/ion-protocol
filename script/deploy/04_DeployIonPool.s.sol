// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { IonPool } from "../../src/IonPool.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { InterestRate } from "../../src/InterestRate.sol";
import { CREATEX } from "../../src/Constants.sol";
import { ICreateX } from "../../src/interfaces/ICreateX.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

import { console2 } from "forge-std/console2.sol";

contract DeployIonPoolScript is DeployScript {
    using StdJson for string;
    using SafeCast for uint256;

    string configPath = "./deployment-config/04_DeployIonPool.json";
    string config = vm.readFile(configPath);

    address underlying = config.readAddress(".underlying");
    address treasury = config.readAddress(".treasury");
    uint8 decimals = config.readUint(".decimals").toUint8();
    string name = config.readString(".name");
    string symbol = config.readString(".symbol");
    InterestRate interestRateModule = InterestRate(config.readAddress(".interestRateModule"));
    Whitelist whitelist = Whitelist(config.readAddress(".whitelist"));
    bytes32 salt = config.readBytes32(".salt");

    function createX() public returns (IonPool ionPool) {
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

        IonPool ionImpl = new IonPool();

        bytes memory initCode = type(TransparentUpgradeableProxy).creationCode;

        address proxy =
            CREATEX.deployCreate3(salt, abi.encodePacked(initCode, abi.encode(ionImpl, initialDefaultAdmin, initData)));

        ionPool = IonPool(proxy);
    }

    // broadcasts with
    function run() public broadcast returns (IonPool ionPool) {
        return createX();
    }

    // runs without broadcast to test with vm.prank as the createX public key
    function runWithoutBroadcast() public returns (IonPool ionPool) {
        return createX();
    }
}
