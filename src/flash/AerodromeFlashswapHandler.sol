// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonHandlerBase } from "./IonHandlerBase.sol";
import { WadRayMath } from "../libraries/math/WadRayMath.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "../interfaces/IPool.sol";

import {console} from "forge-std/Test.sol";

interface IPoolCallee {
    function hook(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}


/**
 * @notice This contract allows for easy creation and closing of leverage
 * positions through Uniswap flashswaps--flashloan not necessary! In terms of
 * creation, this may be a more desirable path than directly minting from an LST
 * provider since market prices tend to be slightly lower than provider exchange
 * rates. DEXes also provide an avenue for atomic deleveraging since the LST ->
 * ETH exchange can be made.
 *
 * @dev When using the `UniswapFlashSwapHandler`, the `IUniswapV3Pool pool` fed to the
 * constructor should be the WETH/[LST] pool.
 *
 * This flow can be used in case when the UniswapV3 Pool has a collateral <>
 * base asset pair. However, the current version of this contract always assumes
 * that the base asset is `WETH`.
 *
 * Unlike Balancer flashloans, there is no concern here that somebody else could
 * initiate a flashswap, then direct the callback to be called on this contract.
 * Uniswap enforces that callback is only called on `msg.sender`.
 *
 * @custom:security-contact security@molecularlabs.io
 */
abstract contract AerodromeFlashswapHandler is IonHandlerBase, IPoolCallee {
    using WadRayMath for *;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    error InvalidUniswapPool();
    error InvalidZeroLiquidityRegionSwap();
    error InvalidSqrtPriceLimitX96(uint160 sqrtPriceLimitX96);

    error FlashswapRepaymentTooExpensive(uint256 amountIn, uint256 maxAmountIn);
    error CallbackOnlyCallableByPool(address unauthorizedCaller);
    error OutputAmountNotReceived(uint256 amountReceived, uint256 amountRequired);

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    IPool public immutable AERODROME_POOL;
    bool private immutable WETH_IS_TOKEN0;

    /**
     * @notice Creates a new `UniswapFlashswapHandler` instance.
     * @param _pool Pool to perform the flashswap on.
     * @param _wethIsToken0 Whether WETH is token0 or token1 in the pool.
     */
    constructor(IPool _pool, bool _wethIsToken0) {
        if (address(_pool) == address(0)) revert InvalidUniswapPool();

        address token0 = _pool.token0();
        address token1 = _pool.token1();

        // I added this
        // require(_wethIsToken0 && token0 == address(WETH) || !_wethIsToken0 && token1 == address(WETH), "incorrect weth is token 0");

        if (token0 != address(WETH) && token1 != address(WETH)) revert InvalidUniswapPool();
        if (token0 == address(WETH) && token1 == address(WETH)) revert InvalidUniswapPool();

        AERODROME_POOL = _pool;

        // todo ask jun why this even exists?
        WETH_IS_TOKEN0 = token0 == address(WETH);
        console.log("WETH is token0? ", token0 == address(WETH));
    }

    struct FlashSwapData {
        address user;
        // This value will be used for change in collateral during leveraging and change in (normalized) debt during
        // deleveraging
        uint256 poolKBefore;
        uint256 changeInCollateralOrDebt;
        bool zeroForOne;
    }

    /**
     * @notice Transfer collateral from user -> initiate swap for collateral from
     * WETH on Uniswap (contract will receive collateral first) -> deposit all
     * collateral into `IonPool` -> borrow WETH from `IonPool` -> complete swap
     * by sending WETH to Uniswap.
     *
     * @param initialDeposit in collateral terms. [WAD]
     * @param resultingAdditionalCollateral in collateral terms. [WAD]
     * @param maxResultingAdditionalDebt in WETH terms. This value also allows
     * the user to control slippage of the swap. [WAD]
     * @param sqrtPriceLimitX96 for the swap. Recommended value is the current
     * exchange rate to ensure the swap never costs more than a direct mint
     * would. Passing the current exchange rate means swapping beyond that point
     * is worse than direct minting.
     * @param deadline timestamp for which the transaction must be executed.
     * This prevents txs that have sat in the mempool for too long to be
     * executed.
     * @param proof that the user is whitelisted.
     */
    function flashswapLeverage(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingAdditionalDebt,
        uint160 sqrtPriceLimitX96,
        uint256 deadline,
        bytes32[] calldata proof
    )
        external
        checkDeadline(deadline)
        onlyWhitelistedBorrowers(proof)
    {
        LST_TOKEN.safeTransferFrom(msg.sender, address(this), initialDeposit);
        _flashswapLeverage(initialDeposit, resultingAdditionalCollateral, maxResultingAdditionalDebt, sqrtPriceLimitX96);
    }

    /**
     * TODO replace swETH comments with ezETH
     * @param initialDeposit in terms of swETH
     * @param resultingAdditionalCollateral in terms of swETH. How much
     * collateral to add to the position in the vault.
     * @param maxResultingAdditionalDebt in terms of WETH. How much debt to add
     * to the position in the vault.
     * @param sqrtPriceLimitX96 for the swap. Recommended value is the current
     * exchange rate to ensure the swap never costs more than a direct mint
     * would.
     */
    function _flashswapLeverage(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingAdditionalDebt,
        uint160 sqrtPriceLimitX96
    )
        internal
    {
        uint256 amountToLeverage = resultingAdditionalCollateral - initialDeposit; // in swETH

        if (amountToLeverage == 0) {
            // AmountToBorrow.IS_MAX because we don't want to create any new debt here
            _depositAndBorrow(msg.sender, address(this), resultingAdditionalCollateral, 0, AmountToBorrow.IS_MAX);
            return;
        }

        // Flashswap WETH for collateral. We will return the WETH inside the Uniswap
        // callback
        // zeroForOne is WETH -> collateral
        bool zeroForOne = WETH_IS_TOKEN0;

        console.log("Amount Out: ", amountToLeverage);
        console.log("Before K: ", AERODROME_POOL.getK());
        FlashSwapData memory flashswapData = FlashSwapData({
            user: msg.sender,
            poolKBefore: AERODROME_POOL.getK(),
            changeInCollateralOrDebt: resultingAdditionalCollateral,
            zeroForOne: zeroForOne
        });

        uint256 amountIn =
            _initiateFlashSwap(zeroForOne, amountToLeverage, address(this), sqrtPriceLimitX96, flashswapData);

        // todo make this work with new variables
        // This protects against a potential sandwich attack
        if (amountIn > maxResultingAdditionalDebt) {
            revert FlashswapRepaymentTooExpensive(amountIn, maxResultingAdditionalDebt);
        }
    }

    /**
     * @notice Initiate swap for WETH from collateral (contract will receive
     * WETH first) -> repay debt on `IonPool` -> withdraw (and gem-exit)
     * collateral from `IonPool` -> complete swap by sending collateral to
     * Uniswap.
     *
     * @dev The two function parameters must be chosen carefully. If
     * `maxCollateralToRemove`'s ETH valuation were higher then `debtToRemove`,
     * it would theoretically be possible to sell more collateral then was
     * required for `debtToRemove` to be repaid (even if `debtToRemove` is worth
     * nowhere near that valuation) due to the slippage of the sell.
     * `maxCollateralToRemove` is essentially a slippage guard here.
     * @param maxCollateralToRemove he max amount of collateral user is willing
     * to sell to repay `debtToRemove` debt. [WAD]
     * @param debtToRemove The desired amount of debt to remove. [WAD]
     * @param sqrtPriceLimitX96 for the swap. Can be set to 0 to set max bounds.
     */
    function flashswapDeleverage(
        uint256 maxCollateralToRemove,
        uint256 debtToRemove,
        uint160 sqrtPriceLimitX96,
        uint256 deadline
    )
        external
        checkDeadline(deadline)
    {
        if (debtToRemove == type(uint256).max) {
            (debtToRemove,) = _getFullRepayAmount(msg.sender);
        }

        if (debtToRemove == 0) return;

        // collateral -> WETH
        bool zeroForOne = !WETH_IS_TOKEN0;

        // todo make deleverage work
        FlashSwapData memory flashswapData =
            FlashSwapData({ user: msg.sender, poolKBefore: AERODROME_POOL.getK(), changeInCollateralOrDebt: debtToRemove, zeroForOne: zeroForOne });

        uint256 amountIn = _initiateFlashSwap(zeroForOne, debtToRemove, address(this), sqrtPriceLimitX96, flashswapData);

        if (amountIn > maxCollateralToRemove) revert FlashswapRepaymentTooExpensive(amountIn, maxCollateralToRemove);
    }

    /**
     * @notice Handles swap initiation logic. This function can only initiate
     * exact output swaps.
     * @param zeroForOne Direction of the swap.
     * @param amountOut Desired amount of output.
     * @param recipient of output tokens.
     * @param sqrtPriceLimitX96 of the swap.
     * @param data Arbitrary data to be passed through swap callback.
     */
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
        if ((sqrtPriceLimitX96 < MIN_SQRT_RATIO || sqrtPriceLimitX96 > MAX_SQRT_RATIO) && sqrtPriceLimitX96 != 0) {
            revert InvalidSqrtPriceLimitX96(sqrtPriceLimitX96);
        }

        console.log("ZeroForOne? If leverage, is == WETH_TOKEN0: ", zeroForOne);
        // the following are AerodromePool.swap()s first 3 inputs:
        // @param amount0Out   Amount of token0 to send to `to`
        // @param amount1Out   Amount of token1 to send to `to`
        // @param to           Address to recieve the swapped output
        // todo assuming token0 is weth. Find out if this is always true.
        if(zeroForOne){
            console.log("Token1(): ", AERODROME_POOL.token1());
            AERODROME_POOL.swap(0, amountOut, recipient, abi.encode(data));
        }else{
            AERODROME_POOL.swap(amountOut, 0, recipient, abi.encode(data));
        }
        
        // it's technically possible to not receive the full output amount,
        // todo Check if this is true ^
    }

    // todo, rewrite below
    // KEY DIFFERENCE 
    // NOT FROM PERSPECTIVE OF POOL
    // Unlike Uniswap, Aerodrome does this from the high level swap perspective. AmountOut means amount out to user. Not amount out to pool.
    //
    // also be sure only the intentioned caller (this) can trigger this probably using sender
    // /**
    //  * @notice From the perspective of the pool i.e. Negative amount means pool is
    //  * sending. This function is intended to never be called directly. It should
    //  * only be called by the Uniswap pool during a swap initiated by this
    //  * contract.
    //  *
    //  * @dev One thing to note from a security perspective is that the pool only calls
    //  * the callback on `msg.sender`. So a theoretical attacker cannot call this
    //  * function by directing where to call the callback.
    //  *
    //  * @param amount0Delta change in token0
    //  * @param amount1Delta change in token1
    //  * @param _data arbitrary data
    //  */
    function hook(address sender, uint256 amount0, uint256 amount1, bytes calldata _data) external override {
        if (msg.sender != address(AERODROME_POOL)) revert CallbackOnlyCallableByPool(msg.sender);

        // swaps entirely within 0-liquidity regions are not supported
        if (amount0 == 0 && amount1 == 0) revert InvalidZeroLiquidityRegionSwap();
        FlashSwapData memory data = abi.decode(_data, (FlashSwapData));

        // todo rename LST to LRT
        // todo see if zero for one is reasonable here?
        (address tokenIn, address tokenOut) =
            data.zeroForOne ? (address(WETH), address(LST_TOKEN)) : (address(LST_TOKEN), address(WETH));

        // Code below this if statement will always assume token0 is WETH. If it
        // is not actually the case, we will flip the vars
        (uint reserve0, uint reserve1,) = AERODROME_POOL.getReserves();
        if (!WETH_IS_TOKEN0) {
            (amount0, amount1) = (amount1, amount0);
            (tokenIn, tokenOut) = (tokenOut, tokenIn);
            (reserve0, reserve1) = (reserve1, reserve0);
        }

        console.log("HOOK EXECUTED");
        // amount 0 is the amount of amount of base tokens we are repaying our loan with
        console.log("Amount0: ", amount0);
        console.log("TokenIn: ", tokenIn);
        // amount1 is the amount of collateral tokens (ezETH) we are leveraging by depositing and borrowing back the tokens to pay for swap
        console.log("Amount1: ", amount1);
        console.log("TokenOut: ", tokenOut);
        console.log("Balance of this in Collateral: ", LST_TOKEN.balanceOf(address(this)));
        console.log("Balance of this in WETH: ", WETH.balanceOf(address(this)));

        uint256 amountToPay;
        // leverage
        if(amount1 > 0){
            console.log("leverage");
            // console.log("User Balance of Token 0: ",IERC20(tokenIn).balanceOf(data.user));
            // amountToPay = AERODROME_POOL.getAmountOut(amount0, tokenIn);
            console.log("Change in col: ", data.changeInCollateralOrDebt);
            // uint kBefore = (reserve0 * reserve1);
            // uint tokenOutBalOfPool = IERC20(tokenOut).balanceOf(address(AERODROME_POOL));
            // uint tokenInBalOfPool = IERC20(tokenIn).balanceOf(address(AERODROME_POOL)) * (10000 - 30) / 10000;
            // amountToPay = (kBefore / tokenOutBalOfPool ) - tokenInBalOfPool;

            /*
                F = Fee multiplier (ex. 1 - 0.3%)
                a = amount Token Out
                x = out token reserve BEFORE a was taken out
                y = in token reserve BEFORE amountToPay is returned
                b = amountToPay of in token

                (x * y) = (x) * (y + b)

                =
                a * y / F(x - a)
            */
            uint a = amount1;
            uint y = IERC20(tokenIn).balanceOf(address(AERODROME_POOL));
            uint x = IERC20(tokenOut).balanceOf(address(AERODROME_POOL));

            amountToPay = (10030 * a * y) / ((10000*x) - (10000 + 30)*a);
            
            // uint getAmountOut = AERODROME_POOL.getAmountOut(amount1, tokenOut);
            // console.log("Amount by getAmountOut", getAmountOut);
            // console.log("K by getAmountOut: ", (x - a) * (y + getAmountOut));

            console.log("Amount to Pay: ", amountToPay);
            _depositAndBorrow(
                data.user, address(this), data.changeInCollateralOrDebt, amountToPay, AmountToBorrow.IS_MIN
            );
            console.log("Balance of this in Collateral: ", LST_TOKEN.balanceOf(address(this)));
            console.log("Balance of this in WETH: ", WETH.balanceOf(address(this)));
        }
        // deleverage
        else {
            console.log("deleverage");
            // console.log("User Balance of Token 1: ",IERC20(tokenIn).balanceOf(data.user));
            // amountToPay = AERODROME_POOL.getAmountOut(amount1, tokenIn);
            amountToPay = AERODROME_POOL.getAmountOut(amount0, tokenOut);
            _repayAndWithdraw(data.user, address(this), amountToPay, data.changeInCollateralOrDebt);
        }
        console.log("sending back: ", amountToPay);
        console.log("of: ", tokenIn);
        IERC20(tokenIn).safeTransfer(msg.sender, amountToPay);
        console.log("After K: ", WETH.balanceOf(address(AERODROME_POOL)) * LST_TOKEN.balanceOf(address(AERODROME_POOL)));
    }
}
