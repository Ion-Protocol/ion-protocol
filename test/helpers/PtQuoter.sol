// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IPMarketV3 } from "pendle-core-v2-public/interfaces/IPMarketV3.sol";
import { IPMarketSwapCallback } from "pendle-core-v2-public/interfaces/IPMarketSwapCallback.sol";

contract PtQuoter is IPMarketSwapCallback {
    // 0xfd2dc465
    error SwapData(uint256 quote);

    function quoteSyForExactPt(IPMarketV3 market, uint256 ptAmount) external returns (uint256) {
        try market.swapSyForExactPt(address(this), ptAmount, hex"01") { }
        catch (bytes memory returndata) {
            assembly {
                let selector := shr(0xe0, mload(add(returndata, 0x20)))
                if and(eq(returndatasize(), 0x24), eq(selector, 0xfd2dc465)) {
                    let syAmount := mload(add(returndata, 0x24))
                    mstore(0x00, syAmount)
                    return(0x00, 0x20)
                }
            }
        }

        revert("PtQuoter: quoteSyForExactPt failed");
    }

    function swapCallback(int256 ptToAccount, int256 syToAccount, bytes calldata) external pure {
        if (syToAccount < 0) revert SwapData(uint256(-syToAccount));
        else if (ptToAccount < 0) revert SwapData(uint256(-ptToAccount));
        revert SwapData(0);
    }
}
