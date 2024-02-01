// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { WETH_ADDRESS, STETH_ADDRESS, WSTETH_ADDRESS } from "../../src/Constants.sol"; 
import { IonPool } from "../../src/IonPool.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { IWETH9 } from "../../src/interfaces/IWETH9.sol";
import { IWstEth } from "../../src/interfaces/ProviderInterfaces.sol";
import { IonZapper } from "../../src/periphery/IonZapper.sol";
import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";
import { BaseScript } from "../Base.s.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { console2 } from "forge-std/Script.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployIonZapperScript is BaseScript {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    string configPath = "./deployment-config/10_DeployIonZapper.json";
    string config = vm.readFile(configPath);

    function run() public broadcast returns (IonZapper ionZapper) {
        IonPool ionPool = IonPool(vm.parseJsonAddress(config, ".ionPool"));
        
        // stEth, wstEth, wstEthJoin kept for constructor compatibility, 
        // But the `zapJoinWstEth` function should simply not be used.  
        
        // IERC20 stEth = IERC20(vm.parseJsonAddress(config, ".stEth"));
        // IWstEth wstEth = IWstEth(vm.parseJsonAddress(config, ".wstEth"));
        
        // GemJoin wstEthJoin = GemJoin(vm.parseJsonAddress(config, ".wstEthJoin"));
        
        // TODO: Either change constructor or approve correctly 
        GemJoin wstEthJoin = GemJoin(address(this)); 
        
        Whitelist whitelist = Whitelist(vm.parseJsonAddress(config, ".whitelist"));

        ionZapper = new IonZapper(ionPool, IWETH9(WETH_ADDRESS), IERC20(STETH_ADDRESS), IWstEth(WSTETH_ADDRESS), wstEthJoin, whitelist);
    }
}
