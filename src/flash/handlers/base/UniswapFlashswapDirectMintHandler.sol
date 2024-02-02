// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonHandlerBase } from "./IonHandlerBase.sol";
import { IWETH9 } from "../../../interfaces/IWETH9.sol";
import { SpotOracle } from "../../../oracles/spot/SpotOracle.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

import { IVault, IERC20 as IERC20Balancer } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { WEETH_ADDRESS, WSTETH_ADDRESS } from "../../../Constants.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

/**
 * @notice This contract allows for easy creation of leverge positions through a
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

    uint256 private flashloanInitiated = 1;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant MIN_SQRT_RATIO = 4_295_128_739;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;

    SpotOracle public immutable SPOT;
    IUniswapV3Pool public immutable UNISWAP_POOL;
    bool private immutable WETH_IS_TOKEN0;

    constructor(IUniswapV3Pool _uniswapPool) {
        if (address(_uniswapPool) == address(0)) revert InvalidUniswapPool();

        address token0 = _uniswapPool.token0();
        address token1 = _uniswapPool.token1();

        if (token0 != address(WETH) && token1 != address(WETH)) {
            revert InvalidUniswapPool();
        }
        if (token0 == address(WETH) && token1 == address(WETH)) {
            revert InvalidUniswapPool();
        }

        UNISWAP_POOL = _uniswapPool;
        WETH_IS_TOKEN0 = token0 == address(WETH) ? true : false;
        SPOT = POOL.spot(ILK_INDEX);
    }

    /**
     * @notice
     * @param initialDeposit in collateral terms. [WAD]
     * @param resultingAdditionalCollateral in collateral terms. [WAD]
     * @param maxResultingDebt in base asset terms. [WAD]
     * @param proof used to validate the user is whitelisted.
     */
    function flashloanWethMintAndSwap(
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
        _flashloanWethMintAndSwap(initialDeposit, resultingAdditionalCollateral, maxResultingDebt);
    }

    function _flashloanWethMintAndSwap(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt
    )
        internal
    {
        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(WETH));

        uint256 amountLrt = resultingAdditionalCollateral - initialDeposit; // in collateral terms
        uint256 amountWethToFlashloan = _getEthAmountInForLstAmountOut(amountLrt);

        if (amountWethToFlashloan == 0) {
            // AmountToBorrow.IS_MAX because we don't want to create any new debt here
            _depositAndBorrow(msg.sender, address(this), resultingAdditionalCollateral, 0, AmountToBorrow.IS_MAX);
            return;
        }

        if (amountWethToFlashloan > maxResultingDebt) {
            revert FlashloanRepaymentTooExpensive(amountWethToFlashloan, maxResultingDebt);
        }

        // We want to swap for ETH here
        bool zeroForOne = WETH_IS_TOKEN0 ? false : true;
        _initiateFlashSwap({
            zeroForOne: zeroForOne,
            amountOut: amountWethToFlashloan,
            recipient: address(this),
            data: abi.encode(msg.sender, zeroForOne, resultingAdditionalCollateral, initialDeposit)
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

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external override {
        if (msg.sender != address(UNISWAP_POOL)) revert CallbackOnlyCallableByPool(msg.sender);

        // swaps entirely within 0-liquidity regions are not supported
        if (amount0Delta == 0 && amount1Delta == 0) revert InvalidZeroLiquidityRegionSwap();
        (address user, bool zeroForOne, uint256 resultingAdditionalCollateral, uint256 initialDeposit) =
            abi.decode(_data, (address, bool, uint256, uint256));

        (address tokenIn, address tokenOut) =
            zeroForOne ? (address(WETH), address(WSTETH_ADDRESS)) : (address(WSTETH_ADDRESS), address(WETH));

        // Code below this if statement will always assume token0 is WETH. If it
        // is not actually the case, we will flip the vars
        if (!WETH_IS_TOKEN0) {
            (amount0Delta, amount1Delta) = (amount1Delta, amount0Delta);
            tokenIn = tokenOut;
        }

        // Sanity check that Uniswap is sending WETH
        assert(amount0Delta < 0 && amount1Delta > 0);

        // Flashloaned WETH needs to be converted into collateral asset
        uint256 collateralFromDeposit = _depositWethForLrt(uint256(-amount0Delta));

        // Sanity check
        assert(collateralFromDeposit + initialDeposit == resultingAdditionalCollateral);

        // AmountToBorrow.IS_MIN because we want to make sure enough is borrowed
        // to cover the amount owed back to Uniswap
        _depositAndBorrow(
            user, address(this), resultingAdditionalCollateral, uint256(amount1Delta), AmountToBorrow.IS_MIN
        );

        IERC20(tokenIn).safeTransfer(msg.sender, uint256(amount1Delta));
    }

    function _depositWethForLrt(uint256 amountWeth) internal virtual returns (uint256);

    /**
     * @notice Calculates the amount of eth required to receive `amountLrt`.
     * @dev Calculates the amount of eth required to receive `amountLrt`.
     * @param amountLrt Desired output amount. [WAD]
     * @return Eth required for desired lst output. [WAD]
     */
    function _getEthAmountInForLstAmountOut(uint256 amountLrt) internal view virtual returns (uint256);
}
