// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandlerBase } from "./IonHandlerBase.sol";

import { IUniswapV3FlashCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import { IUniswapV3PoolActions } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IAsset } from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { console2 } from "forge-std/console2.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

/**
 * @dev Some tokens only have liquidity on Balancer. Due to the reentrancy lock
 * on the Balancer vault, utilizing their free flashloan followed by a pool swap
 * is not possible. Instead, we will take a cheap (0.01%) flashloan from the
 * wstETH/ETH uniswap pool and perform the Balancer swap. The rETH/ETH uniswap
 * pool could also be used since it has a 0.01% but it does have less liquidity.
 */

abstract contract UniswapFlashloanHandler is IUniswapV3FlashCallback, IonHandlerBase {
    using SafeERC20 for IERC20;

    IUniswapV3PoolActions public immutable flashloanPool;
    bool immutable wethIsToken0;

    IVault internal constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    uint256 private flashloanInitiated = 1;

    constructor(IUniswapV3PoolActions _flashloanPool) {
        flashloanPool = _flashloanPool;
    }

    /**
     * @notice Uniswap flashloan do incur a fee
     * @param initialDeposit in collateral terms
     * @param resultingCollateral in collateral terms
     * @param maxResultingDebt in WETH terms.
     */
    function flashLeverageWeth(
        uint256 initialDeposit,
        uint256 resultingCollateral,
        uint256 maxResultingDebt
    )
        external
        payable
    {
        // lstToken.safeTransferFrom(msg.sender, address(this), initialDeposit);

        uint256 collateralToLeverage = resultingCollateral - initialDeposit;

        IVault.SingleSwap memory balancerSwap = IVault.SingleSwap({
            poolId: bytes32(0x37b18b10ce5635a84834b26095a0ae5639dcb7520000000000000000000005cb),
            kind: IVault.SwapKind.GIVEN_OUT,
            assetIn: IAsset(address(weth)),
            assetOut: IAsset(address(lstToken)),
            amount: collateralToLeverage,
            userData: ""
        });

        IVault.FundManagement memory fundManagement = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(this),
            toInternalBalance: false
        });

        IAsset[] memory assets = new IAsset[](2);
        assets[0] = IAsset(address(weth));
        assets[1] = IAsset(address(lstToken));

        IVault.BatchSwapStep memory swapStep = IVault.BatchSwapStep({
            poolId: bytes32(0x37b18b10ce5635a84834b26095a0ae5639dcb7520000000000000000000005cb),
            assetInIndex: 0,
            assetOutIndex: 1,
            amount: collateralToLeverage,
            userData: ""
        });

        IVault.BatchSwapStep[] memory swapSteps = new IVault.BatchSwapStep[](1);
        swapSteps[0] = swapStep;

        int256[] memory a = vault.queryBatchSwap(IVault.SwapKind.GIVEN_OUT, swapSteps, assets, fundManagement);
        console2.log(a[0]);

        weth.approve(address(vault), type(uint256).max);
        vault.swap(balancerSwap, fundManagement, 200e18, block.timestamp + 1);

        (bool success, bytes memory returnData) = address(vault).staticcall(
            abi.encodeWithSelector(
                IVault.queryBatchSwap.selector, IVault.SwapKind.GIVEN_OUT, swapSteps, assets, fundManagement
            )
        );
        console2.logBytes(returnData);

        // flashloanPool.flash(
        //     address(this),

        // );
    }

    /**
     * @notice Called to `msg.sender` after transferring to the recipient from IUniswapV3Pool#flash.
     * @dev In the implementation you must repay the pool the tokens sent by flash plus the computed fee amounts.
     * The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
     * @param fee0 The fee amount in token0 due to the pool by the end of the flash
     * @param fee1 The fee amount in token1 due to the pool by the end of the flash
     * @param data Any data passed through by the caller via the IUniswapV3PoolActions#flash call
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override { }
}
