// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "../src/IonPool.sol";
import { WeEthHandler } from "../src/flash/handlers/WeEthHandler.sol";
import { Whitelist } from "../src/Whitelist.sol";
import { IWstEth, IWeEth } from "../src/interfaces/ProviderInterfaces.sol";
import { IWETH9 } from "../src/interfaces/IWETH9.sol";
import { WSTETH_ADDRESS, WEETH_ADDRESS, EETH_ADDRESS } from "../src/Constants.sol";
import { EtherFiLibrary } from "../src/libraries/EtherFiLibrary.sol";
import { LidoLibrary } from "../src/libraries/LidoLibrary.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "./Base.s.sol";

using LidoLibrary for IWstEth;
using EtherFiLibrary for IWeEth;

contract FlashLeverageScript is BaseScript {
    string configPath = "./deployment-config/DeployedAddresses.json";
    string config = vm.readFile(configPath);

    function run() public broadcast {
        IonPool pool = IonPool(vm.parseJsonAddress(config, ".ionPool"));
        WeEthHandler weEthHandler = WeEthHandler(payable(vm.parseJsonAddress(config, ".weEthHandler")));
        Whitelist whitelist = Whitelist(vm.parseJsonAddress(config, ".whitelist"));
        whitelist.approveProtocolWhitelist(address(weEthHandler));
        whitelist.approveProtocolWhitelist(broadcaster);

        pool.updateSupplyCap(1000 ether);
        WSTETH_ADDRESS.depositForLst(500 ether);
        WSTETH_ADDRESS.approve(address(pool), type(uint256).max);
        pool.supply(address(this), WSTETH_ADDRESS.balanceOf(broadcaster), new bytes32[](0));

        pool.addOperator(address(weEthHandler));

        uint256 initialDeposit = 1 ether; // in collateral terms
        uint256 resultingAdditionalCollateral = 3 ether; // in colllateral terms
        uint256 maxResultingDebt = 3 ether;

        WEETH_ADDRESS.approve(address(weEthHandler), type(uint256).max);
        EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
        WEETH_ADDRESS.depositForLrt(initialDeposit * 2);

        weEthHandler.flashswapAndMint(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp + 1_000_000_000_000,
            new bytes32[](0)
        );
    }
}
