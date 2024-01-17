// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandlerBase } from "./IonHandlerBase.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

/**
 * @dev When using the `UniswapFlashSwapHandler`, the `IUniswapV3Pool pool` fed to the
 * constructor should be the WETH/[LST] pool.
 *
 * Unlike Balancer flashloans, there is no concern here that somebody else could
 * initiate a flashswap, then direct the callback to be called on this contract.
 * Uniswap enforces that callback is only called on `msg.sender`.
 */
abstract contract UniswapFlashswapHandler is IonHandlerBase, IUniswapV3SwapCallback {
    using WadRayMath for *;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    error InvalidUniswapPool();
    error InvalidZeroLiquidityRegionSwap();

    error FlashswapRepaymentTooExpensive(uint256 amountIn, uint256 maxAmountIn);
    error CallbackOnlyCallableByPool(address unauthorizedCaller);
    error OutputAmountNotReceived(uint256 amountReceived, uint256 amountRequired);

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    IUniswapV3Pool public immutable UNISWAP_POOL;
    bool private immutable WETH_IS_TOKEN0;

    constructor(IUniswapV3Pool _pool, bool _wethIsToken0) {
        if (address(_pool) == address(0)) revert InvalidUniswapPool();

        address token0 = _pool.token0();
        address token1 = _pool.token1();

        if (token0 != address(WETH) && token1 != address(WETH)) revert InvalidUniswapPool();

        UNISWAP_POOL = _pool;
        WETH_IS_TOKEN0 = _wethIsToken0;
    }

    struct FlashSwapData {
        address user;
        // This value will be used for change in collateral during leveraging and change in (normalized) debt during
        // deleveraging
        uint256 changeInCollateralOrDebt;
        bool zeroForOne;
    }

    /**
     *
     * @param initialDeposit in terms of swEth
     * @param resultingAdditionalCollateral in terms of swEth. How much
     * collateral to add to the position in the vault.
     * @param maxResultingAdditionalDebt in terms of WETH. How much debt to add
     * to the position in the vault.
     * @param sqrtPriceLimitX96 for the swap. Recommended value is the current
     * exchange rate to ensure the swap never costs more than a direct mint
     * would.
     */
    function flashswapLeverage(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingAdditionalDebt,
        uint160 sqrtPriceLimitX96
    )
        external
    {
        LST_TOKEN.safeTransferFrom(msg.sender, address(this), initialDeposit);

        uint256 amountToLeverage = resultingAdditionalCollateral - initialDeposit; // in swEth

        if (amountToLeverage == 0) {
            // AmountToBorrow.IS_MAX because we don't want to create any new debt here
            _depositAndBorrow(msg.sender, address(this), resultingAdditionalCollateral, 0, AmountToBorrow.IS_MAX);
            return;
        }

        // Flashswap WETH for collateral. We will return the WETH inside the Uniswap
        // callback
        // zeroForOne is WETH -> collateral
        bool zeroForOne = WETH_IS_TOKEN0;

        FlashSwapData memory flashswapData = FlashSwapData({
            user: msg.sender,
            changeInCollateralOrDebt: resultingAdditionalCollateral,
            zeroForOne: zeroForOne
        });

        uint256 amountIn =
            _initiateFlashSwap(zeroForOne, amountToLeverage, address(this), sqrtPriceLimitX96, flashswapData);

        // This protects against a potential sandwich attack
        if (amountIn > maxResultingAdditionalDebt) {
            revert FlashswapRepaymentTooExpensive(amountIn, maxResultingAdditionalDebt);
        }
    }

    /**
     * @dev The two function parameters must be chosen carefully. If `maxCollateralToRemove` were higher then
     * `debtToRemove`, it would theoretically be possible TODO: to do what?
     * @param maxCollateralToRemove in terms of swEth
     * @param debtToRemove in terms of WETH [wad]
     * @param sqrtPriceLimitX96 for the swap
     */
    function flashswapDeleverage(
        uint256 maxCollateralToRemove,
        uint256 debtToRemove,
        uint160 sqrtPriceLimitX96
    )
        external
    {
        if (debtToRemove == 0) return;

        // collateral -> WETH
        bool zeroForOne = !WETH_IS_TOKEN0;

        FlashSwapData memory flashswapData =
            FlashSwapData({ user: msg.sender, changeInCollateralOrDebt: debtToRemove, zeroForOne: zeroForOne });

        uint256 amountIn = _initiateFlashSwap(zeroForOne, debtToRemove, address(this), sqrtPriceLimitX96, flashswapData);

        if (amountIn > maxCollateralToRemove) revert FlashswapRepaymentTooExpensive(amountIn, maxCollateralToRemove);
    }

    function _initiateFlashSwap(
        bool zeroForOne,
        uint256 amountOut,
        address recipient,
        uint160 sqrtPriceLimitX96,
        FlashSwapData memory data
    )
        private
        returns (uint256 amountIn)
    {
        (int256 amount0Delta, int256 amount1Delta) = UNISWAP_POOL.swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            sqrtPriceLimitX96 == 0 ? (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1) : sqrtPriceLimitX96,
            abi.encode(data)
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));

        // it's technically possible to not receive the full output amount,
        // so if no price limit has been specified, require this possibility away
        if (sqrtPriceLimitX96 == 0 && amountOutReceived != amountOut) {
            revert OutputAmountNotReceived(amountOutReceived, amountOut);
        }
    }

    /**
     * @dev From the perspective of the pool i.e. Negative amount means pool is
     * sending. This function is intended to never be called directly. It should
     * only be called by the Uniswap pool during a swap initiated by this
     * contract.
     *
     * One thing to note from a security perspective is that the pool only calls
     * the callback on `msg.sender`. So a theoretical attacker cannot call this
     * function by directing where to call the callback.
     *
     * @param amount0Delta change in token0
     * @param amount1Delta change in token1
     * @param _data arbitrary data
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        if (msg.sender != address(UNISWAP_POOL)) revert CallbackOnlyCallableByPool(msg.sender);

        // swaps entirely within 0-liquidity regions are not supported
        if (amount0Delta == 0 && amount1Delta == 0) revert InvalidZeroLiquidityRegionSwap();
        FlashSwapData memory data = abi.decode(_data, (FlashSwapData));

        (address tokenIn, address tokenOut) =
            data.zeroForOne ? (address(WETH), address(LST_TOKEN)) : (address(LST_TOKEN), address(WETH));

        // Code below this if statement will always assume token0 is WETH. If it
        // is not actually the case, we will flip the vars
        if (!WETH_IS_TOKEN0) {
            (amount0Delta, amount1Delta) = (amount1Delta, amount0Delta);
            (tokenIn, tokenOut) = (tokenOut, tokenIn);
        }

        uint256 amountToPay;
        if (amount0Delta > 0) {
            amountToPay = uint256(amount0Delta);

            // Received `amountToLeverage` collateral from flashswap, will borrow
            // necessary WETH from IonPool position to pay back flashswap

            // AmountToBorrow.IS_MIN because we want to make sure enough is borrowed to cover flashloan
            _depositAndBorrow(
                data.user, address(this), data.changeInCollateralOrDebt, amountToPay, AmountToBorrow.IS_MIN
            );
        } else {
            amountToPay = uint256(amount1Delta);

            // Received `debtToRemove` WETH from flashswap, will
            // withdraw necessary collateral from IonPool position to pay back flashswap
            _repayAndWithdraw(data.user, address(this), amountToPay, data.changeInCollateralOrDebt);
        }

        IERC20(tokenIn).safeTransfer(msg.sender, amountToPay);
    }
}
