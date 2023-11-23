// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol"; 
import { Whitelist } from "src/Whitelist.sol";
import { GemJoin } from "src/join/GemJoin.sol";
import { IWETH9 } from "src/interfaces/IWETH9.sol";
import { IWstEth } from "src/interfaces/ProviderInterfaces.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./Base.s.sol";
import { console2 } from "forge-std/Script.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { IonZapper } from "src/periphery/IonZapper.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployIonZapperScript is BaseScript {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    string configPath = "./deployment-config/10_IonZapper.json";
    string config = vm.readFile(configPath);

    function run() public broadcast returns (IonZapper ionZapper) {

        IonPool ionPool = IonPool(vm.parseJsonAddress(config, ".ionPool"));
        IWETH9 weth = IWETH9(vm.parseJsonAddress(config, ".weth"));
        IERC20 stEth = IERC20(vm.parseJsonAddress(config, ".stEth"));
        IWstEth wstEth = IWstEth(vm.parseJsonAddress(config, ".wstEth"));
        GemJoin wstEthJoin = GemJoin(vm.parseJsonAddress(config, ".wstEthJoin"));
        Whitelist whitelist = Whitelist(vm.parseJsonAddress(config, ".whitelist"));

        ionZapper = new IonZapper(
            ionPool,
            weth,
            stEth,
            wstEth,
            wstEthJoin,
            whitelist
        );
    }
}
