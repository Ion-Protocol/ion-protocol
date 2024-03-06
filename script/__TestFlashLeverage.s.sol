// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "../src/IonPool.sol";
import { RsEthHandler } from "../src/flash/handlers/RsEthHandler.sol";
import { Whitelist } from "../src/Whitelist.sol";
import { IWstEth, IWeEth, IRsEth } from "../src/interfaces/ProviderInterfaces.sol";
import { IWETH9 } from "../src/interfaces/IWETH9.sol";
import { WSTETH_ADDRESS, WEETH_ADDRESS, EETH_ADDRESS, RSETH } from "../src/Constants.sol";
import { LidoLibrary } from "../src/libraries/LidoLibrary.sol";
import { KelpDaoLibrary } from "./../src/libraries/KelpDaoLibrary.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./Base.s.sol";

using LidoLibrary for IWstEth;
using KelpDaoLibrary for IRsEth;

contract FlashLeverageScript is BaseScript {
    string configPath = "./deployment-config/DeployedAddresses.json";
    string config = vm.readFile(configPath);

    function run() public broadcast {
        IonPool pool = IonPool(vm.parseJsonAddress(config, ".ionPool"));
        RsEthHandler rsEthHandler = RsEthHandler(payable(vm.parseJsonAddress(config, ".handler")));

        pool.updateSupplyCap(1000 ether);
        WSTETH_ADDRESS.depositForLst(500 ether);
        WSTETH_ADDRESS.approve(address(pool), type(uint256).max);
        pool.supply(address(this), WSTETH_ADDRESS.balanceOf(broadcaster), new bytes32[](0));

        pool.addOperator(address(rsEthHandler));

        uint256 initialDeposit = 2 ether; // in collateral terms
        uint256 resultingAdditionalCollateral = 8 ether; // in collateral terms
        uint256 maxResultingDebt = 15 ether;

        RSETH.approve(address(rsEthHandler), type(uint256).max);
        // EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
        RSETH.depositForLrt(initialDeposit * 2);

        rsEthHandler.flashswapAndMint(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp + 1_000_000_000_000,
            new bytes32[](0)
        );
    }
}
