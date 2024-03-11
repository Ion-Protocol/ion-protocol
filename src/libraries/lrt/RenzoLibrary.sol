// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RENZO_RESTAKE_MANAGER, EZETH } from "../../Constants.sol";
import { WadRayMath, WAD, RAY } from "../math/WadRayMath.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

using Math for uint256;
using WadRayMath for uint256;

/**
 * @title RenzoLibrary
 *
 * @notice A helper library for Renzo-related conversions.
 *
 * @dev The behaviour in minting ezETH is quite strange, so for the sake of the
 * maintenence of this code, we document the behaviour at block 19387902.
 *
 * The following function is invoked to calculate the amount of ezETH to mint
 * given an `ethAmount` to deposit:
 * `calculateMintAmount(totalTVL, ethAmount, totalSupply)`.
 *
 * ```solidity
 * function calculateMintAmount(uint256 _currentValueInProtocol, uint256 _newValueAdded, uint256 _existingEzETHSupply)
 * external pure returns (uint256) {
 *
 *      ...
 *
 *      // Calculate the percentage of value after the deposit
 *      uint256 inflationPercentaage = SCALE_FACTOR * _newValueAdded / (_currentValueInProtocol + _newValueAdded);
 *
 *      // Calculate the new supply
 *      uint256 newEzETHSupply = (_existingEzETHSupply * SCALE_FACTOR) / (SCALE_FACTOR - inflationPercentaage);
 *
 *      // Subtract the old supply from the new supply to get the amount to mint
 *      uint256 mintAmount = newEzETHSupply - _existingEzETHSupply;
 *
 *      if(mintAmount == 0) revert InvalidTokenAmount();
 *      ...
 * }
 * ```
 *
 * The first thing to note here is the increments by which you can mint ezETH.
 * To mint a non-zero amount of ezETH, `newEzETHSupply` must not be equal to
 * `_existingEzETHSupply`. For this to happen, `inflationPercentage` must be
 * non-zero.
 *
 * At block 19387902, the `totalTVL` or (`_currentValueInProtocol`) is
 * `227527390751192406096375`. So the smallest value for `_newValueAdded` (or
 * the ETH deposited) that will produce an `inflationPercentage` of 1 is
 * `227528`. Any deposit amount less than this will not mint any ezETH (in fact,
 * it will revert). This is the first piece of strange behaviour; the minimum
 * amount to deposit to mint any ezETH is `227528` wei. This will mint `226219`
 * ezETH.
 *
 * The second piece of strange behaviour can be noted when increasing the
 * deposit. If it is increased from `227528` to `227529`, the amount of ezETH
 * minted REMAINS `226219`. This is the case all the way until `455054`. This
 * means that if a user deposits anywhere between `226219` and `455054` wei,
 * they will mint `226219` ezETH. This is because the `inflationPercentage`
 * remains at 1. At `455055` wei, the `inflationPercentage` finally increases to
 * 2, and the amount of ezETH minted increases to `452438`. This also means that
 * it is impossible to mint an ezETH value between `226219` and `452438` wei
 * even though the transfer granularity remains 1 wei.
 *
 * One side effect of this second behaviour is the cost of acquisition can be
 * optimized. It's a really small difference but to acquire `226219` ezETH a
 * user should pay `227528` wei instead of any other value between `227528` and
 * `455054` wei.
 *
 * We will call a mintable amount of ezETH a "mint amount" (recall that at block
 * 19387902, a user cannot mint between `226219` and `452438` ezETH). So
 * `226219` and `452438` are mint amounts.
 *
 * We will call the range of values that produce the same amount of ezETH a
 * "mint range". The mint range for `0` ezETH is `0` to `227527` wei and the mint
 * range for `226219` ezETH is `227528` to `455054` wei.
 */
library RenzoLibrary {
    error InvalidAmountOut(uint256 trueAmountOut, uint256 expectedAmountOut);

    /**
     * @notice Returns the amount of ETH required to mint at least
     * `minAmountOut` ezETH and the actual amount of ezETH minted when
     * depositing that amount of ETH.
     *
     * @dev The goal here is to mint at least `minAmountOut` ezETH. So first, we
     * must find the "mint amount" right above `minAmountOut`. This ensures that
     * we mint at least `minAmountOut`. Then we find the minimum amount of ETH
     * required to mint that "mint amount". Essentially, we want to find the
     * lower bound of the "mint range" of the "mint amount" right above
     * `minAmountOut`.
     *
     * @param minAmountOut Minimum amount of ezETH to mint
     * @return ethAmountIn Amount of ETH required to mint the desired amount of
     * ezETH
     * @return amountOut Actual output amount of ezETH
     */
    function getEthAmountInForLstAmountOut(uint256 minAmountOut)
        internal
        view
        returns (uint256 ethAmountIn, uint256 amountOut)
    {
        if (minAmountOut == 0) return (0, 0);

        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();

        // Each `inflationPercentage` maps to a "mint amount" and, therefore, a
        // "mint range". We need to first calculate the `inflationPercentage`
        // that maps to the "mint range" of the `minAmountOut`. (Technically,
        // the `minAmountOut` is unlikely to have its own "mint range" since it
        // probably won't be a "mint amount," but we can find the mint range of
        // the "mint amount" below `minAmountOut`".)
        //
        // To understand the reason for using `minAmountOut - 1`, consider the
        // case where `minAmountOut` is a "mint amount". Continuing with the
        // example from block 19387902, if `minAmountOut` is `226218`, the
        // `inflationPercentage` below would be 0. It would then be incremented
        // to 1 and then when deriving the the true `amountOut` from the
        // incremented `inflationPercentage`, it would get `amountOut = 226219`.
        // However, if `minAmountOut` is `226219`, the `inflationPercentage`
        // below would be 1 and it would be incremented to 2. Then, true
        // `amountOut` would then be `452438` which is unecessarily minting more
        // when the initial "mint amount" was perfect. So we map "mint amount"s
        // to "mint range"s below themselves by substracting 1. Underflow
        // avoided by the check for `minAmountOut == 0` at the start of the
        // function.
        uint256 ethAmount = _calculateDepositAmount(totalTVL, minAmountOut - 1);
        if (ethAmount == 0) return (0, 0);
        uint256 inflationPercentage = WAD * ethAmount / (totalTVL + ethAmount);

        // Once we have the `inflationPercentage` mapping to the "mint amount"
        // below `minAmountOut`, we increment it to find the
        // `inflationPercentage` mapping to the "mint amount" above
        // `minAmountOut".
        ++inflationPercentage;

        // Then we go on to calculate the ezETH amount and optimal eth deposit
        // mapping to that `inflationPercentage`.
        uint256 totalSupply = EZETH.totalSupply();

        // Calculate the new supply
        uint256 newEzETHSupply = (totalSupply * WAD) / (WAD - inflationPercentage);

        amountOut = newEzETHSupply - totalSupply;

        ethAmountIn = inflationPercentage.mulDiv(totalTVL, WAD - inflationPercentage, Math.Rounding.Ceil);
    }

    /**
     * @notice Returns the amount of ezETH that will be minted with the provided
     * `ethAmount` and the optimal amount of ETH to acquire the same amount of
     * ezETH.
     *
     * @param ethAmount amount of eth to use to mint
     * @return amount of ezETH minted
     * @return optimalAmount optimal amount of ETH required to mint (at the bottom
     * of the mint range)
     */
    function getLstAmountOutForEthAmountIn(uint256 ethAmount)
        internal
        view
        returns (uint256 amount, uint256 optimalAmount)
    {
        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();

        amount = _calculateMintAmount(totalTVL, ethAmount, EZETH.totalSupply());
        optimalAmount = _calculateDepositAmount(totalTVL, amount);
    }

    function depositForLrt(uint256 ethAmount) internal returns (uint256 ezEthAmountToMint) {
        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();

        ezEthAmountToMint = _calculateMintAmount(totalTVL, ethAmount, EZETH.totalSupply());
        RENZO_RESTAKE_MANAGER.depositETH{ value: ethAmount }(0);
    }

    /**
     * @notice Returns the amount of ETH required to mint amountOut ezETH.
     *
     * @dev This function does NOT account for the rounding errors in the ezETH.
     * It simply performs the minting calculation in reverse. To use this
     * function properly, `amountOut` should be a "mint amount" (an amount of
     * ezETH that is actually possible to mint).
     *
     * @param totalTVL Total TVL in the system.
     * @param amountOut Desired amount of ezETH to mint.
     */
    function _calculateDepositAmount(uint256 totalTVL, uint256 amountOut) private view returns (uint256) {
        if (amountOut == 0) return 0;

        //        uint256 mintAmount = newEzETHSupply - _existingEzETHSupply;
        //
        // Solve for newEzETHSupply
        uint256 newEzEthSupply = (amountOut + EZETH.totalSupply());
        uint256 newEzEthSupplyRay = newEzEthSupply.scaleUpToRay(18);

        //        uint256 newEzETHSupply = (_existingEzETHSupply * SCALE_FACTOR) / (SCALE_FACTOR -
        // inflationPercentage);
        //
        // Solve for inflationPercentage
        uint256 intem = EZETH.totalSupply().scaleUpToRay(18).mulDiv(RAY, newEzEthSupplyRay);
        uint256 inflationPercentage = RAY - intem;

        //         uint256 inflationPercentage = SCALE_FACTOR * _newValueAdded / (_currentValueInProtocol +
        // _newValueAdded);
        //
        // Solve for _newValueAdded
        uint256 ethAmountRay = inflationPercentage.mulDiv(totalTVL.scaleUpToRay(18), RAY - inflationPercentage);

        // Truncate from RAY to WAD with roundingUp plus one extra
        // The one extra to get into the next mint range
        uint256 ethAmount = ethAmountRay / 1e9 + 1;
        if (ethAmountRay % 1e9 != 0) ++ethAmount;

        return ethAmount;
    }

    /**
     * @notice Calculates the amount of ezETH that will be minted.
     *
     * @dev This function emulates the calculations in the Renzo contract
     * (including rounding errors).
     *
     * @param _currentValueInProtocol The TVL in the protocol (in ETH terms).
     * @param _newValueAdded The amount of ETH to deposit.
     * @param _existingEzETHSupply The current supply of ezETH.
     * @return The amount of ezETH that will be minted.
     */
    function _calculateMintAmount(
        uint256 _currentValueInProtocol,
        uint256 _newValueAdded,
        uint256 _existingEzETHSupply
    )
        private
        pure
        returns (uint256)
    {
        // For first mint, just return the new value added.
        // Checking both current value and existing supply to guard against gaming the initial mint
        if (_currentValueInProtocol == 0 || _existingEzETHSupply == 0) {
            return _newValueAdded; // value is priced in base units, so divide by scale factor
        }

        // Calculate the percentage of value after the deposit
        uint256 inflationPercentage = WAD * _newValueAdded / (_currentValueInProtocol + _newValueAdded);

        // Calculate the new supply
        uint256 newEzETHSupply = (_existingEzETHSupply * WAD) / (WAD - inflationPercentage);

        // Subtract the old supply from the new supply to get the amount to mint
        uint256 mintAmount = newEzETHSupply - _existingEzETHSupply;

        return mintAmount;
    }
}
