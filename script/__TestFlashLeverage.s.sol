// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { WstEthHandler } from "src/flash/handlers/WstEthHandler.sol";
import { EthXHandler } from "src/flash/handlers/EthXHandler.sol";
import { SwEthHandler } from "src/flash/handlers/SwEthHandler.sol";
import { IWstEth, IStaderStakePoolsManager, ISwEth } from "src/interfaces/ProviderInterfaces.sol";
import { LidoLibrary } from "src/libraries/LidoLibrary.sol";
import { StaderLibrary } from "src/libraries/StaderLibrary.sol";
import { SwellLibrary } from "src/libraries/SwellLibrary.sol";
import { IWETH9 } from "src/interfaces/IWETH9.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { BaseScript } from "script/Base.s.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { console2 } from "forge-std/console2.sol";

IWstEth constant WST_ETH = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
IStaderStakePoolsManager constant MAINNET_STADER = IStaderStakePoolsManager(0xcf5EA1b38380f6aF39068375516Daf40Ed70D299);
ISwEth constant MAINNET_SWELL = ISwEth(0xf951E335afb289353dc249e82926178EaC7DEd78);

IERC20 constant MAINNET_ETHX = IERC20(0xA35b1B31Ce002FBF2058D22F30f95D405200A15b);

IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

using LidoLibrary for IWstEth;
using StaderLibrary for IStaderStakePoolsManager;
using SwellLibrary for ISwEth;

contract FlashLeverageScript is BaseScript {
    string configPath = "./deployment-config/DeployedAddresses.json";
    string config = vm.readFile(configPath);
    
    function run() public broadcast {

        IonPool pool = IonPool(vm.parseJsonAddress(config, ".ionPool")); 
        WstEthHandler wstEthHandler = WstEthHandler(payable(vm.parseJsonAddress(config, ".wstEthHandler")));
        EthXHandler ethXHandler = EthXHandler(payable(vm.parseJsonAddress(config, ".ethXHandler")));
        SwEthHandler swEthHandler = SwEthHandler(payable(vm.parseJsonAddress(config, ".swEthHandler")));
        
        pool.updateSupplyCap(1000 ether);
        WETH.deposit{ value: 500 ether }();
        WETH.approve(address(pool), type(uint256).max);
        pool.supply(address(this), 500 ether, new bytes32[](0));

        WST_ETH.depositForLst(100 ether);
        MAINNET_STADER.depositForLst({ ethAmount: 100 ether, receiver: broadcaster });
        MAINNET_SWELL.depositForLst(100 ether);

        IERC20(address(WST_ETH)).approve(address(wstEthHandler), type(uint256).max);
        MAINNET_ETHX.approve(address(ethXHandler), type(uint256).max);
        IERC20(address(MAINNET_SWELL)).approve(address(swEthHandler), type(uint256).max);

        pool.addOperator(address(wstEthHandler));
        pool.addOperator(address(ethXHandler));
        pool.addOperator(address(swEthHandler));

        uint256 initialDeposit = 1 ether; // in collateral terms
        uint256 resultingAdditionalCollateral = 3 ether; // in colllateral terms
        uint256 maxResultingDebt = WST_ETH.getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        wstEthHandler.flashLeverageCollateral({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        wstEthHandler.flashLeverageWeth({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        wstEthHandler.flashswapLeverage({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingAdditionalDebt: type(uint256).max,
            sqrtPriceLimitX96: 0
        });

        maxResultingDebt = MAINNET_STADER.getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        ethXHandler.flashLeverageCollateral({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        ethXHandler.flashLeverageWeth({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        ethXHandler.flashLeverageWethAndSwap({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingAdditionalDebt: type(uint256).max
        });

        maxResultingDebt = MAINNET_SWELL.getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        swEthHandler.flashLeverageCollateral({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        swEthHandler.flashLeverageWeth({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        swEthHandler.flashswapLeverage({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingAdditionalDebt: type(uint256).max,
            sqrtPriceLimitX96: 0
        });

        uint256 maxCollateralToRemove = 1 ether;
        uint256 debtToRemove = 0.5 ether;

        wstEthHandler.flashswapDeleverage({
            maxCollateralToRemove: maxCollateralToRemove,
            debtToRemove: debtToRemove,
            sqrtPriceLimitX96: 0
        });
        ethXHandler.flashDeleverageWethAndSwap({
            maxCollateralToRemove: maxCollateralToRemove,
            debtToRemove: debtToRemove
        });
        swEthHandler.flashswapDeleverage({
            maxCollateralToRemove: maxCollateralToRemove,
            debtToRemove: debtToRemove,
            sqrtPriceLimitX96: 0
        });
    }
}
