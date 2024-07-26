// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonHandlerBase } from "./IonHandlerBase.sol";
import { WadRayMath } from "../libraries/math/WadRayMath.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IIonPool} from "../interfaces/IIonPool.sol";

import {console} from "forge-std/Test.sol";

interface IPoolCallee {
    function hook(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

interface IPoolFactory {
    function getFee(address pool, bool isStable) external view returns (uint256);
}

/**
 * @notice This contract allows for easy creation and closing of leverage
 * positions through Aerodrome flashswaps--flashloan not necessary! In terms of
 * creation, this may be a more desirable path than directly minting from an LRT/LST
 * provider since market prices tend to be slightly lower than provider exchange
 * rates. DEXes also provide an avenue for atomic deleveraging since the LRT/LST ->
 * ETH exchange can be made.
 *
 * @dev When using the `AerodromeFlashSwapHandler`, the `IPool pool` fed to the
 * constructor should be the WETH/[LRT/LST] pool.
 *
 * This flow can be used in case when the Aerodrome Pool has a collateral <>
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
    error ZeroAmountIn();
    error AmountInTooHigh(uint256 amountIn, uint256 maxAmountIn);

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    IPool public immutable AERODROME_POOL;
    bool private immutable WETH_IS_TOKEN0;

    /**
     * @notice Creates a new `AerodromeFlashswapHandler` instance.
     * @param _pool Pool to perform the flashswap on.
     */
    constructor(IPool _pool, bool /*_wethIsToken0*/){
        if (address(_pool) == address(0)) revert InvalidUniswapPool();

        address token0 = _pool.token0();
        address token1 = _pool.token1();

        // I added this
        // require(_wethIsToken0 && token0 == address(WETH) || !_wethIsToken0 && token1 == address(WETH), "incorrect weth is token 0");

        if (token0 != address(WETH) && token1 != address(WETH)) revert InvalidUniswapPool();
        if (token0 == address(WETH) && token1 == address(WETH)) revert InvalidUniswapPool();

        AERODROME_POOL = _pool;

        WETH_IS_TOKEN0 = token0 == address(WETH);
    }

    struct FlashSwapData {
        address user;
        uint256 changeInCollateralOrDebt;
        uint256 amountToPay;
        address tokenIn;
        address tokenOut;
        bool isLeverage;
    }

    /**
     * @notice Transfer collateral from user -> initiate swap for collateral from
     * WETH on Aerodrome (contract will receive collateral first) -> deposit all
     * collateral into `IonPool` -> borrow WETH from `IonPool` -> complete swap
     * by sending WETH to Aerodrome.
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
     * @param initialDeposit in terms of LRT
     * @param resultingAdditionalCollateral in terms of LRT. How much
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

        // Flashswap WETH for LRT collateral. We will receive collateral first and then
        // return the WETH inside the Uniswap callback

        console.log("Amount Out: ", amountToLeverage);
        console.log("Before K: ", AERODROME_POOL.getK());
        console.log("balance of pool in collateral pre: ", LST_TOKEN.balanceOf(address(AERODROME_POOL)));
        console.log("balance of pool in WETH pre: ", WETH.balanceOf(address(AERODROME_POOL)));
        // leverage case token going in to pool is WETH and coming from pool to handler is collateral token
        (uint256 reserveIn, uint256 reserveOut,) = AERODROME_POOL.getReserves();
        uint256 balanceIn = WETH.balanceOf(address(AERODROME_POOL));
        uint256 balanceOut = LST_TOKEN.balanceOf(address(AERODROME_POOL));
        if (!WETH_IS_TOKEN0) {
            (reserveIn, reserveOut) = (reserveOut, reserveIn);
        }
        if(reserveIn != balanceIn || reserveOut != balanceOut){
            console.log("Reserves and balances are not equal");
            // sync balances with reserves to avoid cases where there are unpredictable fee calculations
            IPool(address(AERODROME_POOL)).sync();
        }
        // revert if trying to take all (or more) of the collateral
        if(amountToLeverage >= balanceOut){
            revert AmountInTooHigh(amountToLeverage, balanceOut);
        }

        uint256 amountToPay = _calculateAmountToPay(balanceIn, balanceOut, amountToLeverage, balanceIn*balanceOut);
        console.log("Amount to Pay: ", amountToPay);

        // This protects against a potential sandwich attack
        if (amountToPay > maxResultingAdditionalDebt) revert FlashswapRepaymentTooExpensive(amountToPay, maxResultingAdditionalDebt);

        FlashSwapData memory flashswapData = FlashSwapData({
            user: msg.sender,
            changeInCollateralOrDebt: resultingAdditionalCollateral,
            amountToPay: amountToPay,
            tokenIn: address(WETH),
            tokenOut: address(LST_TOKEN),
            isLeverage: true
        });

        _initiateFlashSwap(WETH_IS_TOKEN0, amountToLeverage, address(this), sqrtPriceLimitX96, flashswapData);

        console.log("AfterK actual ", AERODROME_POOL.getK());
        console.log("balance of pool in collateral post: ", LST_TOKEN.balanceOf(address(AERODROME_POOL)));
        console.log("balance of pool in WETH post: ", WETH.balanceOf(address(AERODROME_POOL)));
    }

    /**
     * @notice Initiate swap for WETH from collateral (contract will receive
     * WETH first) -> repay debt on `IonPool` -> withdraw (and gem-exit)
     * collateral from `IonPool` -> complete swap by sending collateral to
     * Aerodrome.
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

        console.log("Before K: ", AERODROME_POOL.getK());
        console.log("balance of pool in collateral pre: ", LST_TOKEN.balanceOf(address(AERODROME_POOL)));
        console.log("balance of pool in WETH pre: ", WETH.balanceOf(address(AERODROME_POOL)));

        (uint256 reserveOut, uint256 reserveIn,) = AERODROME_POOL.getReserves();
        uint256 balanceIn = LST_TOKEN.balanceOf(address(AERODROME_POOL));
        uint256 balanceOut = WETH.balanceOf(address(AERODROME_POOL));
        if (!WETH_IS_TOKEN0) {
            (reserveOut, reserveIn) = (reserveIn, reserveOut);
        }
        if(reserveOut != balanceOut || reserveIn != balanceIn){
            console.log("Reserves and balances are not equal");
            // sync balances with reserves to avoid cases where there are unpredictable fee calculations
            IPool(address(AERODROME_POOL)).sync();
        }

        // revert if trying to take all (or more) of the weth
        if(debtToRemove >= balanceOut){
            revert AmountInTooHigh(debtToRemove, balanceOut);
        }
        uint256 amountToPay = _calculateAmountToPay(balanceIn, balanceOut, debtToRemove, balanceIn*balanceOut);

        // This protects against a potential sandwich attack
        if (amountToPay > maxCollateralToRemove) revert FlashswapRepaymentTooExpensive(amountToPay, maxCollateralToRemove);

        FlashSwapData memory flashswapData = FlashSwapData({ 
            user: msg.sender,
            changeInCollateralOrDebt: debtToRemove,
            amountToPay: amountToPay,
            tokenIn: address(LST_TOKEN),
            tokenOut: address(WETH),
            isLeverage: false
        });

        _initiateFlashSwap(!WETH_IS_TOKEN0, debtToRemove, address(this), sqrtPriceLimitX96, flashswapData);
        
        console.log("AfterK actual ", AERODROME_POOL.getK());
        console.log("balance of pool in collateral post: ", LST_TOKEN.balanceOf(address(AERODROME_POOL)));
        console.log("balance of pool in WETH post: ", WETH.balanceOf(address(AERODROME_POOL)));
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
    {
        if ((sqrtPriceLimitX96 < MIN_SQRT_RATIO || sqrtPriceLimitX96 > MAX_SQRT_RATIO) && sqrtPriceLimitX96 != 0) {
            revert InvalidSqrtPriceLimitX96(sqrtPriceLimitX96);
        }
        // the following are AerodromePool.swap()s first 3 inputs:
        // @param amount0Out   Amount of token0 to send to `to`
        // @param amount1Out   Amount of token1 to send to `to`
        // @param to           Address to recieve the swapped output
        if(zeroForOne){
            AERODROME_POOL.swap(0, amountOut, recipient, abi.encode(data));
        }else{
            AERODROME_POOL.swap(amountOut, 0, recipient, abi.encode(data));
        }
    }

    /**
     * @notice From the perspective of the pool. This function is intended to never be called directly. It should
     * only be called by the Aerodrome pool during a swap initiated by this
     * contract.
     *
     * @dev One thing to note from a security perspective is that the pool only calls
     * the callback on `msg.sender`. So a theoretical attacker cannot call this
     * function by directing where to call the callback.
     *
     * @param amount0 change in token0
     * @param amount1 change in token1
     * @param _data flashswap data
     */
    function hook(address, uint256 amount0, uint256 amount1, bytes calldata _data) external override {
        if (msg.sender != address(AERODROME_POOL)) revert CallbackOnlyCallableByPool(msg.sender);

        // swaps entirely within 0-liquidity regions are not supported
        if (amount0 == 0 && amount1 == 0) revert InvalidZeroLiquidityRegionSwap();
        FlashSwapData memory data = abi.decode(_data, (FlashSwapData));

        address tokenIn = data.tokenIn;
        address tokenOut = data.tokenOut;
        uint256 amountToPay = data.amountToPay;
        console.log("Amount To pay", amountToPay);

        console.log("HOOK EXECUTED");
        console.log("Amount0: ", amount0);
        console.log("Amount1: ", amount1);
        console.log("TokenIn: ", tokenIn);
        console.log("TokenOut: ", tokenOut);
        console.log("Balance of this in Collateral: ", LST_TOKEN.balanceOf(address(this)));
        console.log("Balance of this in WETH: ", WETH.balanceOf(address(this)));
        console.log("Balance of pool in collateral start of hook: ", LST_TOKEN.balanceOf(address(AERODROME_POOL)));
        console.log("Balance of pool in WETH start of hook: ", WETH.balanceOf(address(AERODROME_POOL)));

        // leverage case
        if(data.isLeverage){
            console.log("leverage");
            console.log("Change in col: ", data.changeInCollateralOrDebt);
            _depositAndBorrow(
                data.user, address(this), data.changeInCollateralOrDebt, amountToPay, AmountToBorrow.IS_MIN
            );
            console.log("Balance of this in Collateral: ", LST_TOKEN.balanceOf(address(this)));
            console.log("Balance of this in WETH: ", WETH.balanceOf(address(this)));
        }
        // deleverage case
        else {
            console.log("deleverage");
            _repayAndWithdraw(data.user, address(this), amountToPay, data.changeInCollateralOrDebt);
            console.log("Balance of this in Collateral: ", LST_TOKEN.balanceOf(address(this)));
            console.log("Balance of this in WETH: ", WETH.balanceOf(address(this)));
        }
        console.log("sending back: ", amountToPay);
        console.log("of: ", tokenIn);
        IERC20(tokenIn).safeTransfer(msg.sender, amountToPay);

        console.log("Balance of this in Collateral end of hook: ", LST_TOKEN.balanceOf(address(this)));
        console.log("Balance of this in WETH end of hook: ", WETH.balanceOf(address(this)));
        console.log("Balance of pool in collateral end of hook: ", LST_TOKEN.balanceOf(address(AERODROME_POOL)));
        console.log("Balance of pool in WETH end of hook: ", WETH.balanceOf(address(AERODROME_POOL)));
        console.log("After K manual: ", (IERC20(tokenIn).balanceOf(address(AERODROME_POOL)) - 30*amountToPay / 10000 )* (IERC20(tokenOut).balanceOf(address(AERODROME_POOL))));
    }

    function getAmountOutGivenAmountIn (uint256 amountIn, bool isLeverage) external view returns(uint256 amountOut){
        if(amountIn == 0){
            revert ZeroAmountIn();
        }
        uint256 balanceWeth = WETH.balanceOf(address(AERODROME_POOL));
        uint256 balanceCollateral = LST_TOKEN.balanceOf(address(AERODROME_POOL));
        uint256 maxAmountIn = isLeverage ? balanceCollateral : balanceWeth;
        if(amountIn >= maxAmountIn){
            revert AmountInTooHigh(amountIn, maxAmountIn);
        }
        if(isLeverage){
            return _calculateAmountToPay(balanceWeth, balanceCollateral, amountIn, balanceWeth*balanceCollateral);
        }
        return _calculateAmountToPay(balanceCollateral, balanceWeth, amountIn, balanceWeth*balanceCollateral);
    }

    //     F = Fee multiplier e.g. 0.3% for 30 bps
    //     a = amount Token Out from pool (e.g. LRT for leverage or WETH for deleverage)
    //     balOut = out token reserve BEFORE a was taken out (after sync is called will be current initial balance)
    //     balIn = in token reserve initially (after sync is called will be current initial balance)
    //     b = amountToPay of in token (this is unknown and what we are solving for)
    //
    //     balOut * balIn = (balOut - a) * (balIn + b(1-F)) =>
    //     balOut * balIn = balOut * balIn - a * balIn + balOut * b(1-F) - a * b(1-F) =>
    //     a * balIn = b(1-F)(balOut - a) =>
    //     a * balIn / [(1-F)(balOut - a)] = b => note* 1-F = (10000 - fee)/ 10000
    //     10000 * a * balIn / [(10000 - fee) * (balOut - a)] = b

    function _calculateAmountToPay(uint256 balIn, uint256 balOut, uint256 amountChangeCollOrDebt, uint256 poolKBefore) internal view returns(uint256 amountToPay){
        address factory = AERODROME_POOL.factory();
        uint256 fee = IPoolFactory(factory).getFee(address(AERODROME_POOL), false);
        uint256 a = amountChangeCollOrDebt;

        amountToPay = (10000 * a * balIn ) / (9970 * (balOut-a));

        uint256 afterK = (balIn + amountToPay - (fee*amountToPay) / 10000 )* (balOut - a);
        
        if(afterK < poolKBefore){
            console.log("K is less than before");
            amountToPay += 1;
        }
        else{
            console.log("K is greater than before");
        }
        console.log("Amount to Pay inside helper: ", amountToPay);
        console.log("afterK inside helper: ", afterK);
        return amountToPay;
    }
}
