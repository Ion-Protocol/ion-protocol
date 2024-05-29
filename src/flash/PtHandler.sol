// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { IonPool } from "../IonPool.sol";
import { GemJoin } from "../join/GemJoin.sol";
import { Whitelist } from "../Whitelist.sol";
import { IonHandlerBase } from "./IonHandlerBase.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPMarketSwapCallback } from "pendle-core-v2-public/interfaces/IPMarketSwapCallback.sol";
import { IPMarketV3 } from "pendle-core-v2-public/interfaces/IPMarketV3.sol";
import { IStandardizedYield } from "pendle-core-v2-public/interfaces/IStandardizedYield.sol";
import { IPPrincipalToken } from "pendle-core-v2-public/interfaces/IPPrincipalToken.sol";
import { IPYieldToken } from "pendle-core-v2-public/interfaces/IPYieldToken.sol";

/**
 * @notice This contract allows for easy creation of leverage positions for PT
 * collateralized Ion markets.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract PtHandler is IonHandlerBase, IPMarketSwapCallback {
    error InvalidGemJoin(address invalidJoin);
    error MarketMustBeCaller(address caller);
    error ExternalFlashswapNotAllowed();
    error InvalidSwapDirection();
    error UnexpectedSyOut(uint256 amountSyOut, uint256 expectedSyOut);
    error FlashswapTooExpensive(uint256 amountSyIn, uint256 maxResultingDebt);

    IPMarketV3 public immutable MARKET;

    IStandardizedYield public immutable SY;
    IERC20 public immutable PT;
    IERC20 public immutable YT;

    uint256 private flashswapInitiated = 1;

    /**
     * @notice Creates a new `PtHandler` instance
     * @param pool The related IonPool.
     * @param join The related GemJoin.
     * @param whitelist The whitelist contract.
     * @param _market The related Pendle market.
     */
    constructor(
        IonPool pool,
        GemJoin join,
        Whitelist whitelist,
        IPMarketV3 _market
    )
        IonHandlerBase(0, pool, join, whitelist)
    {
        if (!pool.hasRole(pool.GEM_JOIN_ROLE(), address(join))) revert InvalidGemJoin(address(join));

        (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT) = _market.readTokens();

        if (join.GEM() != _PT) revert InvalidGemJoin(address(join));

        SY = _SY;
        PT = _PT;
        YT = _YT;

        BASE.approve(address(_SY), type(uint256).max);

        MARKET = _market;
    }

    /**
     * @notice Allows a borrower to create a leveraged position on Ion Protocol
     * @dev Transfer PT from user -> Flashswap PT token -> Deposit all PT into
     * IonPool -> Borrow base asset -> Mint SY using base asset -> Repay
     * Flashswap with SY.
     */
    function ptLeverage(
        uint256 initialDeposit,
        uint256 resultingAdditionalCollateral,
        uint256 maxResultingDebt,
        uint256 deadline,
        bytes32[] calldata proof
    )
        external
        onlyWhitelistedBorrowers(proof)
        checkDeadline(deadline)
    {
        PT.transferFrom(msg.sender, address(this), initialDeposit);

        uint256 ptToFlashswap = resultingAdditionalCollateral - initialDeposit;

        if (ptToFlashswap == 0) {
            _depositAndBorrow(msg.sender, address(this), resultingAdditionalCollateral, 0, AmountToBorrow.IS_MAX);
            return;
        }

        flashswapInitiated = 2;

        MARKET.swapSyForExactPt(
            address(this), ptToFlashswap, abi.encode(resultingAdditionalCollateral, maxResultingDebt, msg.sender)
        );

        flashswapInitiated = 1;
    }

    /**
     * @notice This function should never be called directly.
     *
     * @dev On small enough swaps, the SY to send back can be 0.
     *
     * This function can only be called by the market.
     *
     * This function can only be called by market if the swap was initiated by
     * this contract.
     *
     * @param ptToAccount Amount of PT sent from the perspective of the pool (negative means pool is sending, positive
     * means user is receiving)
     * @param syToAccount Amount of SY sent from the perspective of the pool (negative means pool is sending, positive
     * means user is receiving)
     * @param data Arbitrary data passed by the market
     */
    function swapCallback(int256 ptToAccount, int256 syToAccount, bytes calldata data) external {
        if (msg.sender != address(MARKET)) revert MarketMustBeCaller(msg.sender);
        if (flashswapInitiated == 1) revert ExternalFlashswapNotAllowed();

        (uint256 resultingAdditionalCollateral, uint256 maxResultingDebt, address user) =
            abi.decode(data, (uint256, uint256, address));

        // On small enough swaps,
        if (ptToAccount <= 0 || syToAccount > 0) revert InvalidSwapDirection();
        uint256 syToSend = uint256(-syToAccount);

        // This check assumes that SY is pegged to the BASE asset.
        // If it isn't, it will revert later in this call.
        if (syToSend > maxResultingDebt) revert FlashswapTooExpensive(syToSend, maxResultingDebt);

        _depositAndBorrow(user, address(this), resultingAdditionalCollateral, syToSend, AmountToBorrow.IS_MIN);

        // Automatically repay the flashswap
        uint256 amountSyOut;
        if (syToSend != 0) amountSyOut = SY.deposit(address(MARKET), address(BASE), syToSend, syToSend);

        // This check guarantees that the SY is pegged to the BASE asset
        if (amountSyOut != syToSend) revert UnexpectedSyOut(amountSyOut, syToSend);
    }
}
