// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { IonPool } from "../../src/IonPool.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { InterestRate } from "../../src/InterestRate.sol";
import { CREATEX } from "../../src/Constants.sol";
import { TransparentUpgradeableProxy } from "../../src/admin/TransparentUpgradeableProxy.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

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

    function createX() public returns (IonPool ionImpl, IonPool ionPool) {
        _validateInterface(IERC20(underlying));
        _validateInterface(interestRateModule);
        _validateInterface(whitelist);

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

        // if (deployCreate2) {
        //     ionImpl = new IonPool{ salt: DEFAULT_SALT }();
        // } else {
        //     ionImpl = new IonPool();
        // }

        ionImpl = IonPool(0xAd71a9e73e235A61caEb10059B64459FAB23B8C7);

        bytes memory initCode = type(TransparentUpgradeableProxy).creationCode;

        address proxy =
            CREATEX.deployCreate3(salt, abi.encodePacked(initCode, abi.encode(ionImpl, initialDefaultAdmin, initData)));

        ionPool = IonPool(proxy);
    }

    // broadcasts with
    function run() public broadcast returns (IonPool ionImpl, IonPool ionPool) {
        return createX();
    }

    // runs without broadcast to test with vm.prank as the createX public key
    function runWithoutBroadcast() public returns (IonPool ionImpl, IonPool ionPool) {
        return createX();
    }
}
