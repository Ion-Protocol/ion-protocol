// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IWETH9 } from "../../../interfaces/IWETH9.sol";
import { IonHandlerBase } from "./IonHandlerBase.sol";
import { IWETH9 } from "../../../interfaces/IWETH9.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3FlashCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";

import { IVault } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";
import { IAsset } from "@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice This contract allows for easy creation and closing of leverage
 * positions through Uniswap flashloans and LST swaps on Balancer. In terms of
 * creation, this may be a more desirable path than directly minting from an LST
 * provider since market prices tend to be slightly lower than provider exchange
 * rates. DEXes also provide an avenue for atomic deleveraging since the LST ->
 * ETH exchange can be made.
 *
 * NOTE: Uniswap flashloans do charge a small fee.
 *
 * @dev Some tokens only have liquidity on Balancer. Due to the reentrancy lock
 * on the Balancer VAULT, utilizing their free flashloan followed by a pool swap
 * is not possible. Instead, we will take a cheap (0.01%) flashloan from the
 * wstETH/ETH uniswap pool and perform the Balancer swap. The rETH/ETH uniswap
 * pool could also be used since it has a 0.01% fee but it does have less
 * liquidity.
 *
 * @custom:security-contact security@molecularlabs.io
 */
abstract contract UniswapFlashloanBalancerSwapHandler is IUniswapV3FlashCallback, IonHandlerBase {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH9;

    error WethNotInPoolPair(IUniswapV3Pool pool);
    error ReceiveCallerNotPool(address unauthorizedCaller);

    IVault internal constant VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    bool immutable WETH_IS_TOKEN0_ON_UNISWAP;
    IUniswapV3Pool public immutable FLASHLOAN_POOL;
    bytes32 public immutable BALANCER_POOL_ID;

    /**
     * @notice Creates a new instance of `UniswapFlashloanBalancerSwapHandler`
     * @param _flashloanPool UniswapV3 pool from which to flashloan
     * @param _balancerPoolId Balancer pool identifier through which to route
     * swaps.
     */
    constructor(IUniswapV3Pool _flashloanPool, bytes32 _balancerPoolId) {
        address weth = address(WETH);
        IERC20(weth).approve(address(VAULT), type(uint256).max);
        IERC20(address(LST_TOKEN)).approve(address(VAULT), type(uint256).max);

        FLASHLOAN_POOL = _flashloanPool;
        address token0 = IUniswapV3Pool(_flashloanPool).token0();
        address token1 = IUniswapV3Pool(_flashloanPool).token1();

        bool _wethIsToken0 = token0 == weth;
        bool _wethIsToken1 = token1 == weth;

        if (!_wethIsToken0 && !_wethIsToken1) revert WethNotInPoolPair(_flashloanPool);

        // Technically possible here for both tokens to be weth, but Uniswap does not allow for this
        WETH_IS_TOKEN0_ON_UNISWAP = _wethIsToken0;

        BALANCER_POOL_ID = _balancerPoolId;
    }

    /**
     * @notice Transfer collateral from user + flashloan WETH from Uniswap ->
     * swap for collateral using WETH on Balancer pool -> deposit all collateral
     * into `IonPool` -> borrow WETH from `IonPool` -> repay Uniswap flashloan + fee.
     *
     * Uniswap flashloans do incur a fee.
     *
     * @param initialDeposit in collateral terms. [WAD]
     * @param resultingAdditionalCollateral in collateral terms. [WAD]
     * @param maxResultingAdditionalDebt in WETH terms. This value also allows
     * the user to control slippage of the swap. [WAD]
     * @param deadline timestamp for which the transaction must be executed.
     * This prevents txs that have sat in the mempool for too long to be
     * executed.
     * @param proof used to validate the user is whitelisted.
     */
    function flashLeverageWethAndSwap(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingAdditionalDebt,
        uint256 deadline,
        bytes32[] calldata proof
    )
        external
        payable
        checkDeadline(deadline)
        onlyWhitelistedBorrowers(proof)
    {
        LST_TOKEN.safeTransferFrom(msg.sender, address(this), initialDeposit);
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
            assetIn: address(WETH),
            assetOut: address(LST_TOKEN),
            amountOut: amountToLeverage
        });

        flashCallbackData.user = msg.sender;
        flashCallbackData.initialDeposit = initialDeposit;
        flashCallbackData.maxResultingAdditionalDebtOrCollateralToRemove = maxResultingAdditionalDebt;
        flashCallbackData.wethFlashloaned = wethIn;
        flashCallbackData.amountToLeverage = amountToLeverage;

        uint256 amount0ToFlash;
        uint256 amount1ToFlash;
        if (WETH_IS_TOKEN0_ON_UNISWAP) amount0ToFlash = wethIn;
        else amount1ToFlash = wethIn;

        FLASHLOAN_POOL.flash(address(this), amount0ToFlash, amount1ToFlash, abi.encode(flashCallbackData));
    }

    /**
     * @notice Flashloan WETH from Uniswap -> repay debt in `IonPool` ->
     * withdraw collateral from `IonPool` -> sell collateral for `WETH` on
     * Balancer -> repay Uniswap flashloan + fee.
     *
     * Uniswap flashloans do incur a fee.
     *
     * @param maxCollateralToRemove The max amount of collateral user is willing
     * to sell to repay `debtToRemove` debt. [WAD]
     * @param debtToRemove The desired amount of debt to remove. [WAD]
     * @param deadline timestamp for which the transaction must be executed.
     * This prevents txs that have sat in the mempool for too long to be
     * executed.
     */
    function flashDeleverageWethAndSwap(
        uint256 maxCollateralToRemove,
        uint256 debtToRemove,
        uint256 deadline
    )
        external
        checkDeadline(deadline)
    {
        if (debtToRemove == type(uint256).max) {
            (debtToRemove,) = _getFullRepayAmount(msg.sender);
        }

        if (debtToRemove == 0) return;

        uint256 amount0ToFlash;
        uint256 amount1ToFlash;
        if (WETH_IS_TOKEN0_ON_UNISWAP) amount0ToFlash = debtToRemove;
        else amount1ToFlash = debtToRemove;

        FLASHLOAN_POOL.flash(
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
     * @notice Called to `msg.sender` after transferring to the recipient from
     * IUniswapV3Pool#flash.
     *
     * @dev In the implementation, you must repay the pool the tokens sent by
     * `flash()` plus the computed fee amounts.
     *
     * The caller of this method must be checked to be a UniswapV3Pool.
     *
     * Initiator is guaranteed to be this contract since UniswapV3 pools will
     * only call the callback on msg.sender.
     *
     * @param fee0 The fee amount in tokenInBalancer due to the pool by the end
     * of the flash
     * @param fee1 The fee amount in tokenOutBalancer due to the pool by the end
     * of the flash
     * @param data Any data passed through by the caller via the
     * IUniswapV3PoolActions#flash call
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external override {
        if (msg.sender != address(FLASHLOAN_POOL)) revert ReceiveCallerNotPool(msg.sender);

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
                poolId: bytes32(BALANCER_POOL_ID),
                kind: IVault.SwapKind.GIVEN_OUT,
                assetIn: IAsset(address(WETH)),
                assetOut: IAsset(address(LST_TOKEN)),
                amount: amountToLeverage,
                userData: ""
            });

            // We will skip slippage control for this step. This is OK since if
            // there was a frontrun attack or the slippage is too high, then the
            // `wethToRepay` value will go above the user's desired
            // `maxResultingAdditionalDebt`
            uint256 wethSent = VAULT.swap(balancerSwap, fundManagement, type(uint256).max, block.timestamp + 1);

            // Sanity check
            assert(wethSent == flashCallbackData.wethFlashloaned);

            uint256 totalCollateral = flashCallbackData.initialDeposit + amountToLeverage;
            _depositAndBorrow(user, address(this), totalCollateral, wethToRepay, AmountToBorrow.IS_MIN);

            WETH.safeTransfer(msg.sender, wethToRepay);
        } else {
            // When deleveraging
            uint256 totalRepayment = flashCallbackData.wethFlashloaned + fee;

            uint256 collateralIn = _simulateGivenOutBalancerSwap({
                fundManagement: fundManagement,
                assetIn: address(LST_TOKEN),
                assetOut: address(WETH),
                amountOut: totalRepayment
            });

            uint256 maxCollateralToRemove = flashCallbackData.maxResultingAdditionalDebtOrCollateralToRemove;
            if (collateralIn > maxCollateralToRemove) {
                revert FlashloanRepaymentTooExpensive(collateralIn, maxCollateralToRemove);
            }

            _repayAndWithdraw(flashCallbackData.user, address(this), collateralIn, flashCallbackData.wethFlashloaned);

            IVault.SingleSwap memory balancerSwap = IVault.SingleSwap({
                poolId: bytes32(BALANCER_POOL_ID),
                kind: IVault.SwapKind.GIVEN_OUT,
                assetIn: IAsset(address(LST_TOKEN)),
                assetOut: IAsset(address(WETH)),
                amount: totalRepayment,
                userData: ""
            });

            VAULT.swap(balancerSwap, fundManagement, type(uint256).max, block.timestamp + 1);

            WETH.safeTransfer(msg.sender, totalRepayment);
        }
    }

    /**
     * @notice Simulates a Balancer swap with a desired amount of `assetOut`.
     * @param fundManagement Balancer fund management struct
     * @param assetIn asset to swap from
     * @param assetOut asset to swap to
     * @param amountOut desired amount of assetOut. Will revert if not received. [WAD]
     */
    function _simulateGivenOutBalancerSwap(
        IVault.FundManagement memory fundManagement,
        address assetIn,
        address assetOut,
        uint256 amountOut
    )
        internal
        returns (uint256)
    {
        uint256 assetInIndex = 0;
        uint256 assetOutIndex = 1;

        IVault.BatchSwapStep memory swapStep = IVault.BatchSwapStep({
            poolId: bytes32(BALANCER_POOL_ID),
            assetInIndex: assetInIndex,
            assetOutIndex: assetOutIndex,
            amount: amountOut,
            userData: ""
        });

        IAsset[] memory assets = new IAsset[](2);
        assets[assetInIndex] = IAsset(assetIn);
        assets[assetOutIndex] = IAsset(assetOut);

        IVault.BatchSwapStep[] memory swapSteps = new IVault.BatchSwapStep[](1);
        swapSteps[0] = swapStep;

        return uint256(VAULT.queryBatchSwap(IVault.SwapKind.GIVEN_OUT, swapSteps, assets, fundManagement)[assetInIndex]);
    }
}
