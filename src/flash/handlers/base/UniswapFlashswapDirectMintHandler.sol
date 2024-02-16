// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonHandlerBase } from "./IonHandlerBase.sol";
import { IWETH9 } from "../../../interfaces/IWETH9.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import { IERC20 as IERC20Balancer } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { WSTETH_ADDRESS } from "../../../Constants.sol";

/**
 * @notice This contract allows for easy creation of leverge positions through a
 * Uniswap flashswap and direct mint of the collateral from the provider. This
 * will be used when the collateral cannot be minted directly with the base
 * asset but can be directly minted by a token that the base asset has a
 * UniswapV3 pool with.
 *
 * This contract is to be used when there exists a UniswapV3 pool between the
 * base asset and the mint asset.
 *
 * @custom:security-contact security@molecularlabs.io
 */
abstract contract UniswapFlashswapDirectMintHandler is IonHandlerBase, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH9;
    using SafeCast for uint256;

    error InvalidUniswapPool();
    error InvalidZeroLiquidityRegionSwap();
    error CallbackOnlyCallableByPool(address unauthorizedCaller);
    error OutputAmountNotReceived(uint256 amountReceived, uint256 amountRequired);

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    IUniswapV3Pool public immutable UNISWAP_POOL;
    IERC20 public immutable MINT_ASSET;
    bool private immutable MINT_IS_TOKEN0;

    /**
     * @notice Creates a new `UniswapFlashswapDirectMintHandler` instance.
     * @param _uniswapPool Pool to perform the flashswap on.
     * @param _mintAsset The asset used to mint the collateral.
     */
    constructor(IUniswapV3Pool _uniswapPool, IERC20 _mintAsset) {
        if (address(_uniswapPool) == address(0)) revert InvalidUniswapPool();

        MINT_ASSET = _mintAsset;

        address token0 = _uniswapPool.token0();
        address token1 = _uniswapPool.token1();

        if (token0 != address(MINT_ASSET) && token1 != address(MINT_ASSET)) {
            revert InvalidUniswapPool();
        }
        if (token0 == address(MINT_ASSET) && token1 == address(MINT_ASSET)) {
            revert InvalidUniswapPool();
        }

        UNISWAP_POOL = _uniswapPool;
        MINT_IS_TOKEN0 = token0 == address(MINT_ASSET) ? true : false;

        address baseAsset = MINT_IS_TOKEN0 ? token1 : token0;

        if (baseAsset != address(BASE)) revert InvalidUniswapPool();
    }

    /**
     * @notice Transfer collateral from user -> Initiate flashswap between from
     * base asset to mint asset -> Use the mint asset to mint the collateral ->
     * Deposit all collateral into `IonPool` -> Borrow the base asset -> Close
     * the flashswap by sending the base asset to the Uniswap pool.
     * @param initialDeposit in collateral terms. [WAD]
     * @param resultingAdditionalCollateral in collateral terms. [WAD]
     * @param maxResultingDebt in base asset terms. [WAD]
     * @param proof used to validate the user is whitelisted.
     */
    function flashswapAndMint(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt,
        uint256 deadline,
        bytes32[] memory proof
    )
        external
        onlyWhitelistedBorrowers(proof)
        checkDeadline(deadline)
    {
        LST_TOKEN.safeTransferFrom(msg.sender, address(this), initialDeposit);
        _flashswapAndMint(initialDeposit, resultingAdditionalCollateral, maxResultingDebt);
    }

    function _flashswapAndMint(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt
    )
        internal
    {
        uint256 amountLrt = resultingAdditionalCollateral - initialDeposit; // in collateral terms
        uint256 amountWethToFlashloan = _getAmountInForCollateralAmountOut(amountLrt);

        if (amountWethToFlashloan == 0) {
            // AmountToBorrow.IS_MAX because we don't want to create any new debt here
            _depositAndBorrow(msg.sender, address(this), resultingAdditionalCollateral, 0, AmountToBorrow.IS_MAX);
            return;
        }

        if (amountWethToFlashloan > maxResultingDebt) {
            revert FlashloanRepaymentTooExpensive(amountWethToFlashloan, maxResultingDebt);
        }

        // We want to swap for ETH here
        bool zeroForOne = MINT_IS_TOKEN0 ? false : true;
        _initiateFlashSwap({
            zeroForOne: zeroForOne,
            amountOut: amountWethToFlashloan,
            recipient: address(this),
            data: abi.encode(msg.sender, resultingAdditionalCollateral, initialDeposit)
        });
    }

    /**
     * @notice Handles swap intiation logic. This function can only initiate
     * exact output swaps.
     * @param zeroForOne Direction of the swap.
     * @param amountOut Desired amount of output.
     * @param recipient of output tokens.
     * @param data Arbitrary data to be passed through swap callback.
     */
    function _initiateFlashSwap(
        bool zeroForOne,
        uint256 amountOut,
        address recipient,
        bytes memory data
    )
        private
        returns (uint256 amountIn)
    {
        (int256 amount0Delta, int256 amount1Delta) = UNISWAP_POOL.swap(
            recipient, zeroForOne, -amountOut.toInt256(), zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1, data
        );

        uint256 amountOutReceived;
        (amountIn, amountOutReceived) = zeroForOne
            ? (uint256(amount0Delta), uint256(-amount1Delta))
            : (uint256(amount1Delta), uint256(-amount0Delta));

        // it's technically possible to not receive the full output amount,
        if (amountOutReceived != amountOut) revert OutputAmountNotReceived(amountOutReceived, amountOut);
    }

    /**
     * @notice From the perspective of the pool i.e. Negative amount means pool is
     * sending. This function is intended to never be called directly. It should
     * only be called by the Uniswap pool during a swap initiated by this
     * contract.
     *
     * @dev One thing to note from a security perspective is that the pool only calls
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
        (address user, uint256 resultingAdditionalCollateral, uint256 initialDeposit) =
            abi.decode(_data, (address, uint256, uint256));

        // Code below this if statement will always assume token0 is MINT_ASSET. If it
        // is not actually the case, we will flip the vars
        if (!MINT_IS_TOKEN0) {
            (amount0Delta, amount1Delta) = (amount1Delta, amount0Delta);
        }

        address tokenIn = address(BASE);

        // Sanity check that Uniswap is sending MINT_ASSET
        assert(amount0Delta < 0 && amount1Delta > 0);

        // MINT_ASSET needs to be converted into collateral asset
        uint256 collateralFromDeposit = _mintCollateralAsset(uint256(-amount0Delta));

        // Sanity check
        assert(collateralFromDeposit + initialDeposit == resultingAdditionalCollateral);

        // AmountToBorrow.IS_MIN because we want to make sure enough is borrowed
        // to cover the amount owed back to Uniswap
        _depositAndBorrow(
            user, address(this), resultingAdditionalCollateral, uint256(amount1Delta), AmountToBorrow.IS_MIN
        );

        IERC20(tokenIn).safeTransfer(msg.sender, uint256(amount1Delta));
    }

    /**
     * @notice Deposits the mint asset into the provider's collateral-asset
     * deposit contract.
     * @param amountMintAsset amount of "mint asset" to deposit. [WAD]
     */
    function _mintCollateralAsset(uint256 amountMintAsset) internal virtual returns (uint256);

    /**
     * @notice Calculates the amount of mint asset required to receive
     * `amountLrt`.
     * @dev Calculates the amount of mint asset required to receive `amountLrt`.
     * @param amountLrt Desired output amount. [WAD]
     * @return Amount mint asset required for desired output. [WAD]
     */
    function _getAmountInForCollateralAmountOut(uint256 amountLrt) internal view virtual returns (uint256);
}
