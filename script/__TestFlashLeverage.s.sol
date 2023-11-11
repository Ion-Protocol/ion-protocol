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

IonPool constant POOL = IonPool(0x92b0d1Cc77b84973B7041CB9275d41F09840eaDd);
IWstEth constant WST_ETH = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
IStaderStakePoolsManager constant MAINNET_STADER = IStaderStakePoolsManager(0xcf5EA1b38380f6aF39068375516Daf40Ed70D299);
ISwEth constant MAINNET_SWELL = ISwEth(0xf951E335afb289353dc249e82926178EaC7DEd78);

IERC20 constant MAINNET_ETHX = IERC20(0xA35b1B31Ce002FBF2058D22F30f95D405200A15b);

WstEthHandler constant WSTETH_HANDLER = WstEthHandler(payable(0xc3b99d27eF3B07C94Ee3cFD670281F0CF98A02f1));
EthXHandler constant ETHX_HANDLER = EthXHandler(payable(0x20F5f006a0184883068bBF58fb0c526A8EEa8BFD));
SwEthHandler constant SWETH_HANDLER = SwEthHandler(payable(0x975cDd867aCB99f0195be09C269E2440aa1b1FA8));

IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

using LidoLibrary for IWstEth;
using StaderLibrary for IStaderStakePoolsManager;
using SwellLibrary for ISwEth;

contract FlashLeverageScript is BaseScript {
    function run() public broadcast {
        POOL.updateSupplyCap(1000 ether);
        WETH.deposit{ value: 500 ether }();
        WETH.approve(address(POOL), type(uint256).max);
        POOL.supply(address(this), 500 ether, new bytes32[](0));

        WST_ETH.depositForLst(100 ether);
        MAINNET_STADER.depositForLst({ ethAmount: 100 ether, receiver: broadcaster });
        MAINNET_SWELL.depositForLst(100 ether);

        IERC20(address(WST_ETH)).approve(address(WSTETH_HANDLER), type(uint256).max);
        MAINNET_ETHX.approve(address(ETHX_HANDLER), type(uint256).max);
        IERC20(address(MAINNET_SWELL)).approve(address(SWETH_HANDLER), type(uint256).max);

        POOL.addOperator(address(WSTETH_HANDLER));
        POOL.addOperator(address(ETHX_HANDLER));
        POOL.addOperator(address(SWETH_HANDLER));

        uint256 initialDeposit = 1 ether; // in collateral terms
        uint256 resultingAdditionalCollateral = 3 ether; // in colllateral terms
        uint256 maxResultingDebt = WST_ETH.getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        WSTETH_HANDLER.flashLeverageCollateral({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        WSTETH_HANDLER.flashLeverageWeth({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        WSTETH_HANDLER.flashswapLeverage({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingAdditionalDebt: type(uint256).max,
            sqrtPriceLimitX96: 0
        });

        maxResultingDebt = MAINNET_STADER.getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        ETHX_HANDLER.flashLeverageCollateral({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        ETHX_HANDLER.flashLeverageWeth({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        ETHX_HANDLER.flashLeverageWethAndSwap({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingAdditionalDebt: type(uint256).max
        });

        maxResultingDebt = MAINNET_SWELL.getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        SWETH_HANDLER.flashLeverageCollateral({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        SWETH_HANDLER.flashLeverageWeth({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingDebt: maxResultingDebt
        });
        SWETH_HANDLER.flashswapLeverage({
            initialDeposit: initialDeposit,
            resultingAdditionalCollateral: resultingAdditionalCollateral,
            maxResultingAdditionalDebt: type(uint256).max,
            sqrtPriceLimitX96: 0
        });

        uint256 maxCollateralToRemove = 1 ether;
        uint256 debtToRemove = 0.5 ether;

        WSTETH_HANDLER.flashswapDeleverage({
            maxCollateralToRemove: maxCollateralToRemove,
            debtToRemove: debtToRemove,
            sqrtPriceLimitX96: 0
        });
        ETHX_HANDLER.flashDeleverageWethAndSwap({
            maxCollateralToRemove: maxCollateralToRemove,
            debtToRemove: debtToRemove
        });
        SWETH_HANDLER.flashswapDeleverage({
            maxCollateralToRemove: maxCollateralToRemove,
            debtToRemove: debtToRemove,
            sqrtPriceLimitX96: 0
        });
    }
}
