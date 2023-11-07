// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandlerBase } from "./IonHandlerBase.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3FlashCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IAsset } from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";
import { console2 } from "forge-std/console2.sol";

/**
 * @dev Some tokens only have liquidity on Balancer. Due to the reentrancy lock
 * on the Balancer vault, utilizing their free flashloan followed by a pool swap
 * is not possible. Instead, we will take a cheap (0.01%) flashloan from the
 * wstETH/ETH uniswap pool and perform the Balancer swap. The rETH/ETH uniswap
 * pool could also be used since it has a 0.01% but it does have less liquidity.
 */
abstract contract UniswapFlashloanBalancerSwapHandler is IUniswapV3FlashCallback, IonHandlerBase {
    using SafeERC20 for IERC20;

    error WethNotInPoolPair(IUniswapV3Pool pool);
    error ReceiveCallerNotPool(address unauthorizedCaller);
    error ExternalUniswapFlashloanNotAllowed();
    error FlashloanRepaymentTooExpensive(uint256 repaymentAmount, uint256 maxRepaymentAmount);

    IVault internal constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    bool immutable wethIsToken0OnUniswap;
    IUniswapV3Pool public immutable flashloanPool;

    constructor(IUniswapV3Pool _flashloanPool) {
        IERC20(address(weth)).approve(address(vault), type(uint256).max);
        IERC20(address(lstToken)).approve(address(vault), type(uint256).max);

        flashloanPool = _flashloanPool;
        address token0 = IUniswapV3Pool(flashloanPool).token0();
        address token1 = IUniswapV3Pool(flashloanPool).token1();

        bool _wethIsToken0 = token0 == address(weth);
        bool _wethIsToken1 = token1 == address(weth);

        if (!_wethIsToken0 && !_wethIsToken1) revert WethNotInPoolPair(flashloanPool);

        // Technically possible here for both tokens to be weth, but Uniswap does not allow for this
        wethIsToken0OnUniswap = _wethIsToken0;
    }

    /**
     * @notice Uniswap flashloan do incur a fee
     * @param initialDeposit in collateral terms
     * @param resultingAdditionalCollateral in collateral terms
     * @param maxResultingAdditionalDebt in WETH terms. This value also allows the user to
     * control slippage of the swap.
     */
    function flashLeverageWethAndSwap(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingAdditionalDebt
    )
        external
        payable
    {
        lstToken.safeTransferFrom(msg.sender, address(this), initialDeposit);
        uint256 amountToLeverage = resultingAdditionalCollateral - initialDeposit;

        if (amountToLeverage == 0) {
            // AmountToBorrow.IS_MAX because we don't want to create any new debt here
            _depositAndBorrow(msg.sender, address(this), resultingAdditionalCollateral, 0, AmountToBorrow.IS_MAX);
            return;
        }

        FlashCallbackData memory flashCallbackData;

        IVault.FundManagement memory fundManagement = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(this),
            toInternalBalance: false
        });

        // We need to know how much weth we will need to pay for our desired
        // amount of collateral output. Once we know this value, we can request
        // the value from the flashloan.
        uint256 wethIn = _simulateGivenOutBalancerSwap({
            fundManagement: fundManagement,
            assetIn: address(weth),
            assetOut: address(lstToken),
            amountIn: amountToLeverage
        });

        flashCallbackData.user = msg.sender;
        flashCallbackData.initialDeposit = initialDeposit;
        flashCallbackData.maxResultingAdditionalDebtOrCollateralToRemove = maxResultingAdditionalDebt;
        flashCallbackData.wethFlashloaned = wethIn;
        flashCallbackData.amountToLeverage = amountToLeverage;

        uint256 amount0ToFlash;
        uint256 amount1ToFlash;
        if (wethIsToken0OnUniswap) amount0ToFlash = wethIn;
        else amount1ToFlash = wethIn;

        flashloanPool.flash(address(this), amount0ToFlash, amount1ToFlash, abi.encode(flashCallbackData));
    }

    function flashDeleverageWethAndSwap(uint256 maxCollateralToRemove, uint256 debtToRemove) external {
        if (debtToRemove == 0) return;

        uint256 amount0ToFlash;
        uint256 amount1ToFlash;
        if (wethIsToken0OnUniswap) amount0ToFlash = debtToRemove;
        else amount1ToFlash = debtToRemove;

        flashloanPool.flash(
            address(this),
            amount0ToFlash,
            amount1ToFlash,
            abi.encode(
                FlashCallbackData({
                    user: msg.sender,
                    initialDeposit: 0,
                    maxResultingAdditionalDebtOrCollateralToRemove: maxCollateralToRemove,
                    wethFlashloaned: debtToRemove,
                    amountToLeverage: 0
                })
            )
        );
    }

    struct FlashCallbackData {
        address user;
        // This value is only used when leveraging
        uint256 initialDeposit;
        // This value will change its meaning depending on the direction of the
        // swap. For leveraging, it is the max resulting additional debt. For
        // deleveraging, it is the max collateral to remove.
        uint256 maxResultingAdditionalDebtOrCollateralToRemove;
        // How much weth was flashloaned from Uniswap. During leveraging this
        // weth will be used to swap for collateral, and during deleveraging
        // this weth will be used to repay IonPool debt.
        uint256 wethFlashloaned;
        // This value indicates the amount of extra collateral that must be
        // borrowed. However, this value is only relevant for leveraging. If
        // this value is zero, then we are deleveraging.
        uint256 amountToLeverage;
    }

    /**
     * @notice Called to `msg.sender` after transferring to the recipient from IUniswapV3Pool#flash.
     * @dev In the implementation you must repay the pool the tokens sent by flash plus the computed fee amounts.
     * The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
     * @param fee0 The fee amount in tokenInBalancer due to the pool by the end of the flash
     * @param fee1 The fee amount in tokenOutBalancer due to the pool by the end of the flash
     * @param data Any data passed through by the caller via the IUniswapV3PoolActions#flash call
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override {
        if (msg.sender != address(flashloanPool)) revert ReceiveCallerNotPool(msg.sender);

        FlashCallbackData memory flashCallbackData = abi.decode(data, (FlashCallbackData));

        IVault.FundManagement memory fundManagement = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(this),
            toInternalBalance: false
        });

        uint256 fee = fee0 + fee1; // At least one of these should be zero, assuming only one token was flashloaned

        if (flashCallbackData.amountToLeverage > 0) {
            uint256 amountToLeverage = flashCallbackData.amountToLeverage;

            address user = flashCallbackData.user;
            uint256 maxResultingAdditionalDebt = flashCallbackData.maxResultingAdditionalDebtOrCollateralToRemove;
            uint256 wethFlashloaned = flashCallbackData.wethFlashloaned;

            uint256 wethToRepay = wethFlashloaned + fee;
            if (wethToRepay > maxResultingAdditionalDebt) {
                revert FlashloanRepaymentTooExpensive(wethToRepay, maxResultingAdditionalDebt);
            }

            IVault.SingleSwap memory balancerSwap = IVault.SingleSwap({
                poolId: bytes32(0x37b18b10ce5635a84834b26095a0ae5639dcb7520000000000000000000005cb),
                kind: IVault.SwapKind.GIVEN_OUT,
                assetIn: IAsset(address(weth)),
                assetOut: IAsset(address(lstToken)),
                amount: amountToLeverage,
                userData: ""
            });

            // We will skip slippage control for this step. This is OK since if
            // there was a frontrun attack or the slippage is too high, then the
            // `wethToRepay` value will go above the user's desired
            // `maxResultingAdditionalDebt`
            uint256 wethSent = vault.swap(balancerSwap, fundManagement, type(uint256).max, block.timestamp + 1);

            // Sanity check
            assert(wethSent == flashCallbackData.wethFlashloaned);

            uint256 totalCollateral = flashCallbackData.initialDeposit + amountToLeverage;
            _depositAndBorrow(user, address(this), totalCollateral, wethToRepay, AmountToBorrow.IS_MIN);

            weth.transfer(msg.sender, wethToRepay);
        } else {
            // When deleveraging
            uint256 totalRepayment = flashCallbackData.wethFlashloaned + fee;

            uint256 collateralIn = _simulateGivenOutBalancerSwap({
                fundManagement: fundManagement,
                assetIn: address(lstToken),
                assetOut: address(weth),
                amountIn: totalRepayment
            });

            uint256 maxCollateralToRemove = flashCallbackData.maxResultingAdditionalDebtOrCollateralToRemove;
            if (collateralIn > maxCollateralToRemove) {
                revert FlashloanRepaymentTooExpensive(collateralIn, maxCollateralToRemove);
            }

            _repayAndWithdraw(flashCallbackData.user, address(this), collateralIn, flashCallbackData.wethFlashloaned);

            IVault.SingleSwap memory balancerSwap = IVault.SingleSwap({
                poolId: bytes32(0x37b18b10ce5635a84834b26095a0ae5639dcb7520000000000000000000005cb),
                kind: IVault.SwapKind.GIVEN_OUT,
                assetIn: IAsset(address(lstToken)),
                assetOut: IAsset(address(weth)),
                amount: totalRepayment,
                userData: ""
            });

            vault.swap(balancerSwap, fundManagement, type(uint256).max, block.timestamp + 1);

            weth.transfer(msg.sender, totalRepayment);
        }
    }

    function _simulateGivenOutBalancerSwap(
        IVault.FundManagement memory fundManagement,
        address assetIn,
        address assetOut,
        uint256 amountIn
    )
        internal
        returns (uint256)
    {
        uint256 assetInIndex = 0;
        uint256 assetOutIndex = 1;

        IVault.BatchSwapStep memory swapStep = IVault.BatchSwapStep({
            poolId: bytes32(0x37b18b10ce5635a84834b26095a0ae5639dcb7520000000000000000000005cb),
            assetInIndex: assetInIndex,
            assetOutIndex: assetOutIndex,
            amount: amountIn,
            userData: ""
        });

        IAsset[] memory assets = new IAsset[](2);
        assets[assetInIndex] = IAsset(address(assetIn));
        assets[assetOutIndex] = IAsset(address(assetOut));

        IVault.BatchSwapStep[] memory swapSteps = new IVault.BatchSwapStep[](1);
        swapSteps[0] = swapStep;

        return uint256(vault.queryBatchSwap(IVault.SwapKind.GIVEN_OUT, swapSteps, assets, fundManagement)[assetInIndex]);
    }
}
