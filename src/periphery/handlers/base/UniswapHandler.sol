// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../IonPool.sol";
import { IonRegistry } from "./../../IonRegistry.sol";
import { IonHandlerBase } from "./IonHandlerBase.sol";
import { RoundedMath } from "../../../libraries/math/RoundedMath.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 as IERC20OZ } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { CallbackValidation } from "../../uniswap/CallbackValidation.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import { IERC20 } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import { console2 } from "forge-std/console2.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

/**
 * @dev When using the `UniswapHandler`, the `IUniswapV3Pool pool` fed to the
 * constructor should be the WETH/[LST] pool.
 */
abstract contract UniswapHandler is IonHandlerBase, IUniswapV3SwapCallback {
    using RoundedMath for *;
    using SafeCast for uint256;
    using SafeERC20 for IERC20OZ;

    error FlashswapRepaymentTooExpensive(uint256 amountIn, uint256 maxAmountIn);
    error CallbackOnlyCallableByPool();
    error InsufficientBalance();

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    uint24 public immutable poolFee;
    IUniswapV3Factory immutable factory;
    IUniswapV3Pool immutable pool;
    bool immutable wethIsToken0;

    uint256 flashSwapInitiated = 1;

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        IonRegistry _ionRegistry,
        IUniswapV3Factory _factory,
        IUniswapV3Pool _pool,
        uint24 _poolFee,
        bool _wethIsToken0
    )
        IonHandlerBase(_ilkIndex, _ionPool, _ionRegistry)
    {
        if (address(_factory) == address(0)) revert InvalidFactoryAddress();
        if (address(_pool) == address(0)) revert InvalidSwEthPoolAddress();

        factory = _factory;
        pool = _pool;
        poolFee = _poolFee;
        wethIsToken0 = _wethIsToken0;
    }

    struct FlashSwapData {
        address user;
        uint256 additionalCollateral;
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
    function flashSwapLeverage(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingAdditionalDebt,
        uint160 sqrtPriceLimitX96
    )
        external
    {
        uint256 amountToLeverage = resultingAdditionalCollateral - initialDeposit; // in swEth

        IERC20(lstToken).transferFrom(msg.sender, address(this), initialDeposit);

        if (amountToLeverage == 0) {
            _depositAndBorrow(msg.sender, address(this), resultingAdditionalCollateral, 0);
            return;
        }

        // Flashswap WETH for collateral. We will return the WETH inside the Uniswap
        // callback
        // zeroForOne is WETH -> collateral
        bool zeroForOne = wethIsToken0;

        FlashSwapData memory flashSwapData = FlashSwapData({
            user: msg.sender,
            additionalCollateral: resultingAdditionalCollateral,
            zeroForOne: zeroForOne
        });

        // Ensures callback is only called when flashswap is initiated by this contract
        flashSwapInitiated = 2;
        uint256 amountIn =
            _initiateFlashSwap(zeroForOne, amountToLeverage, address(this), sqrtPriceLimitX96, flashSwapData);
        flashSwapInitiated = 1;

        // This protects against a potential sandwhich attack
        if (amountIn > maxResultingAdditionalDebt) {
            revert FlashswapRepaymentTooExpensive(amountIn, maxResultingAdditionalDebt);
        }
    }

    // TODO: Reentrancy possibility with leverage and deleverage?
    /**
     * @dev The two function parameters must be chosen carefully. If `maxCollateralToRemove` were higher then
     * `debtToRemove`, it would theoretically be possible
     * @param maxCollateralToRemove in terms of swEth
     * @param debtToRemove in terms of WETH [wad]
     * @param sqrtPriceLimitX96 for the swap
     */
    function flashSwapDeleverage(
        uint256 maxCollateralToRemove,
        uint256 debtToRemove,
        uint160 sqrtPriceLimitX96
    )
        external
    {
        if (debtToRemove == 0) return;

        // collateral -> WETH
        bool zeroForOne = !wethIsToken0;

        FlashSwapData memory flashSwapData =
            FlashSwapData({ user: msg.sender, additionalCollateral: 0, zeroForOne: zeroForOne });

        // This recalculation is necessary because IonPool rounds up repayment
        // calculations... so the amount of weth required to pay off the debt
        // may be slightly higher
        uint256 currentIlkRate = ionPool.rate(ilkIndex);
        uint256 normalizedDebtToRemove = debtToRemove.rayDivDown(currentIlkRate); // [WAD] * [RAY] / [RAY] = [WAD]
        uint256 wethRequired = currentIlkRate.rayMulUp(normalizedDebtToRemove); // [WAD] * [RAY] / [RAY] = [WAD]

        flashSwapInitiated = 2;
        uint256 amountIn = _initiateFlashSwap(zeroForOne, wethRequired, address(this), sqrtPriceLimitX96, flashSwapData);
        flashSwapInitiated = 1;

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
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
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
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }

    /**
     * @dev From the perspective of the pool i.e. Negative amount means pool is
     * sending. This function is intended to never be called directly. It should
     * only be called by the Uniswap pool during a swap initiated by this
     * contract.
     * @param amount0Delta change in WETH
     * @param amount1Delta change in swEth
     * @param _data arbitrary data
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        if (flashSwapInitiated != 2) revert ExternalFlashloanNotAllowed();
        if (msg.sender != address(pool)) revert CallbackOnlyCallableByPool();

        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        FlashSwapData memory data = abi.decode(_data, (FlashSwapData));

        // WETH is token0
        (address tokenIn, address tokenOut) =
            data.zeroForOne ? (address(weth), address(lstToken)) : (address(lstToken), address(weth));

        CallbackValidation.verifyCallback(address(factory), tokenIn, tokenOut, poolFee);

        if (!wethIsToken0) {
            (amount0Delta, amount1Delta) = (amount1Delta, amount0Delta);
            (tokenIn, tokenOut) = (tokenOut, tokenIn);
        }

        uint256 amountToPay;
        if (amount0Delta > 0) {
            amountToPay = uint256(amount0Delta);

            // Received `amountToLeverage` swEth from flashswap, will borrow
            // necessary weth from IonPool position to pay back flashswap
            _depositAndBorrow(data.user, address(this), data.additionalCollateral, amountToPay);
        } else {
            amountToPay = uint256(amount1Delta);

            // Received `normalizedDebtToRemove` weth from flashswap, will
            // withdraw necessary swEth from IonPool position to pay back flashswap
            _repayAndWithdraw(data.user, address(this), amountToPay, uint256(-amount0Delta));
        }

        if (amountToPay > IERC20(tokenIn).balanceOf(address(this))) revert InsufficientBalance();

        IERC20OZ(tokenIn).safeTransfer(msg.sender, amountToPay);
    }
}
