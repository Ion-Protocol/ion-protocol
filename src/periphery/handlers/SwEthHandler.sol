// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../IonPool.sol";
import { IonRegistry } from "./../IonRegistry.sol";
import { IonHandlerBase } from "./IonHandlerBase.sol";
import { ISwellDeposit } from "../../interfaces/DepositInterfaces.sol";
import { RoundedMath, WAD } from "../../math/RoundedMath.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 as IERC20OZ } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { CallbackValidation } from "../uniswap/CallbackValidation.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import { IERC20 } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import { console2 } from "forge-std/console2.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

contract SwEthHandler is IonHandlerBase, IUniswapV3SwapCallback {
    using RoundedMath for *;
    using SafeCast for uint256;
    using SafeERC20 for IERC20OZ;

    error InvalidFactoryAddress();
    error InvalidSwEthPoolAddress();

    error FlashswapRepaymentTooExpensive();
    error CallbackOnlyCallableByPool();
    error InsufficientBalance();

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    uint24 public constant POOL_FEE = 500;

    IUniswapV3Factory immutable factory;
    IUniswapV3Pool immutable swEthPool;

    uint256 flashSwapInitiated = 1;

    constructor(
        uint8 _ilkIndex,
        IonPool _ionPool,
        IonRegistry _ionRegistry,
        IUniswapV3Factory _factory,
        IUniswapV3Pool _swEthPool
    )
        IonHandlerBase(_ilkIndex, _ionPool, _ionRegistry)
    {
        if (address(_factory) == address(0)) revert InvalidFactoryAddress();
        if (address(_swEthPool) == address(0)) revert InvalidSwEthPoolAddress();

        factory = _factory;
        swEthPool = _swEthPool;
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
     */
    function flashSwapLeverage(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingAdditionalDebt
    )
        external
    {
        uint256 amountToLeverage = resultingAdditionalCollateral - initialDeposit; // in swEth

        IERC20(lstToken).transferFrom(msg.sender, address(this), initialDeposit);
        // Flashswap WETH for swEth. We will return the WETH inside the Uniswap
        // callback

        uint256 exchangeRate = ISwellDeposit(address(lstToken)).ethToSwETHRate();
        // If price of the pool ends up being larger than the exchange rate,
        // then a direct 1:1 contract mint is more favorable
        uint160 sqrtPriceLimitX96 = uint160(Math.sqrt(uint256(exchangeRate << 192) / 1e18));

        // zeroForOne is WETH -> swEth
        bool zeroForOne = true;

        FlashSwapData memory flashSwapData = FlashSwapData({
            user: msg.sender,
            additionalCollateral: resultingAdditionalCollateral,
            zeroForOne: zeroForOne
        });

        flashSwapInitiated = 2;
        uint256 amountIn =
            _initiateFlashSwap(zeroForOne, amountToLeverage, address(this), sqrtPriceLimitX96, flashSwapData);
        flashSwapInitiated = 1;

        // This protects against a potential sandwhich attack
        if (amountIn > maxResultingAdditionalDebt) revert FlashswapRepaymentTooExpensive();
    }

    // TODO: Reentrancy possibility with leverage and deleverage
    /**
     * @dev The two function parameters must be chosen carefully. If `maxCollateralToRemove` were higher then
     * `normalizedDebtToRemove`, it would theoretically be possible
     * @param maxCollateralToRemove in terms of swEth
     * @param normalizedDebtToRemove in terms of WETH [wad]
     */
    function flashSwapDeleverage(uint256 maxCollateralToRemove, uint256 normalizedDebtToRemove) external {
        // swEth -> WETH
        bool zeroForOne = false;

        FlashSwapData memory flashSwapData =
            FlashSwapData({ user: msg.sender, additionalCollateral: 0, zeroForOne: zeroForOne });

        uint256 wethRequired = ionPool.rate(ilkIndex).rayMulUp(normalizedDebtToRemove); // [WAD] * [RAY] / [RAY] = [WAD]

        flashSwapInitiated = 2;
        uint256 amountIn =
        // Will turn off sqrtPriceLimitX96 slippage check in favor of the `amountIn < maxCollateralToRemove` check
         _initiateFlashSwap(zeroForOne, wethRequired, address(this), 0, flashSwapData);
        flashSwapInitiated = 1;

        if (amountIn > maxCollateralToRemove) revert FlashswapRepaymentTooExpensive();
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
        (int256 wethDelta, int256 swEthDelta) = swEthPool.swap(
            recipient,
            zeroForOne,
            -amountOut.toInt256(),
            sqrtPriceLimitX96 == 0
                ? (zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1)
                : sqrtPriceLimitX96,
            abi.encode(data)
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) =
            zeroForOne ? (uint256(wethDelta), uint256(-swEthDelta)) : (uint256(swEthDelta), uint256(-wethDelta));
        // it's technically possible to not receive the full output amount,
        // so if no price limit has been specified, require this possibility away
        if (sqrtPriceLimitX96 == 0) require(amountOutReceived == amountOut);
    }

    /**
     * @dev From the perspective of the pool i.e. Negative amount means pool is sending
     * @param wethDelta change in WETH
     * @param swEthDelta change in swEth
     * @param _data arbitrary data
     */
    function uniswapV3SwapCallback(int256 wethDelta, int256 swEthDelta, bytes calldata _data) external override {
        if (flashSwapInitiated != 2) revert ExternalFlashloanNotAllowed();
        if (msg.sender != address(swEthPool)) revert CallbackOnlyCallableByPool();

        require(wethDelta > 0 || swEthDelta > 0); // swaps entirely within 0-liquidity regions are not supported
        FlashSwapData memory data = abi.decode(_data, (FlashSwapData));

        // WETH is token0
        (address tokenIn, address tokenOut) =
            data.zeroForOne ? (address(weth), address(lstToken)) : (address(lstToken), address(weth));

        CallbackValidation.verifyCallback(address(factory), tokenIn, tokenOut, POOL_FEE);

        uint256 amountToPay;
        if (wethDelta > 0) {
            amountToPay = uint256(wethDelta);

            // Received `amountToLeverage` swEth from flashswap, will borrow necessary weth to pay back flashswap
            _depositAndBorrow(data.user, address(this), data.additionalCollateral, amountToPay);
        } else {
            amountToPay = uint256(swEthDelta);

            // Received `normalizedDebtToRemove` weth from flashswap, will withdraw necessary swEth to pay back
            // flashswap
            _repayAndWithdraw(data.user, address(this), amountToPay, uint256(-wethDelta));
        }

        if (amountToPay > IERC20(tokenIn).balanceOf(address(this))) revert InsufficientBalance();

        IERC20OZ(tokenIn).safeTransfer(msg.sender, amountToPay);
    }

    function _getLstAmountOut(uint256 amountWeth) internal view override returns (uint256) {
        // lstToken and depositContract are same
        return ISwellDeposit(address(lstToken)).ethToSwETHRate() * amountWeth / WAD;
    }

    function _depositWethForLst(uint256 amountWeth) internal override returns (uint256) {
        weth.withdraw(amountWeth);

        ISwellDeposit(address(lstToken)).deposit{ value: amountWeth }();

        return _getLstAmountOut(amountWeth);
    }
}
