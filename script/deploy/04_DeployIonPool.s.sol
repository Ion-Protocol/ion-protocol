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
        require(underlying.code.length > 0, "No code at underlying address");
        // Test interface
        IERC20(underlying).totalSupply();
        IERC20(underlying).balanceOf(address(this));
        IERC20(underlying).allowance(address(this), address(this));

        require(address(interestRateModule).code.length > 0, "No code at InterestRate address");
        // Test interface
        interestRateModule.COLLATERAL_COUNT();
        interestRateModule.YIELD_ORACLE();
        interestRateModule.calculateInterestRate(0, 0, 0);

        require(address(whitelist).code.length > 0, "No code at Whitelist address");
        // Test interface
        whitelist.lendersRoot();
        whitelist.borrowersRoot(0);

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

        ionImpl = new IonPool();

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
