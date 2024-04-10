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

contract PtHandler is IonHandlerBase, IPMarketSwapCallback {
    error MarketMustBeCaller(address caller);
    error ExternalFlashswapNotAllowed();
    error InvalidSwapDirection();
    error UnexpectedSyOut(uint256 amountSyOut, uint256 expectedSyOut);
    error FlashswapTooExpensive(uint256 amountSyIn, uint256 maxResultingDebt);

    IPMarketV3 public immutable market;

    IStandardizedYield public immutable SY;
    IERC20 public immutable PT;
    IERC20 public immutable YT;

    uint256 flashswapInitiated = 1;

    constructor(
        IonPool pool,
        GemJoin join,
        Whitelist whitelist,
        IPMarketV3 _market
    )
        IonHandlerBase(0, pool, join, whitelist)
    {
        (IStandardizedYield _SY, IPPrincipalToken _PT, IPYieldToken _YT) = _market.readTokens();

        SY = _SY;
        PT = _PT;
        YT = _YT;

        BASE.approve(address(_SY), type(uint256).max);

        market = _market;
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

        market.swapSyForExactPt(
            address(this), ptToFlashswap, abi.encode(resultingAdditionalCollateral, maxResultingDebt, msg.sender)
        );

        flashswapInitiated = 1;
    }

    // /**
    //  * @dev On small enough swaps, the SY to send back can be 0.
    //  * @param ptToAccount
    //  * @param syToAccount
    //  * @param data
    //  */
    function swapCallback(int256 ptToAccount, int256 syToAccount, bytes calldata data) external {
        if (msg.sender != address(market)) revert MarketMustBeCaller(msg.sender);
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
        if (syToSend != 0) amountSyOut = SY.deposit(address(market), address(BASE), syToSend, syToSend);

        // This check guarantees that the SY is pegged to the BASE asset
        if (amountSyOut != syToSend) revert UnexpectedSyOut(amountSyOut, syToSend);
    }
}
