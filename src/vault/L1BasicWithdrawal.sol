// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "../interfaces/IVault.sol";
import { IXERC20Lockbox } from "../interfaces/IXERC20Lockbox.sol";
import { IXERC20 } from "../interfaces/IXERC20.sol";

import { ForwarderXReceiver } from "./ForwarderXReceiver.sol";

contract L1BasicWithdrawal is ForwarderXReceiver {
    constructor(address _connext) ForwarderXReceiver(_connext) { }

    function _prepare(
        bytes32,
        bytes memory _data,
        uint256 _amount,
        address _asset
    )
        internal
        override
        returns (bytes memory)
    {
        // TODO: Since the receiver gets the tokens, this will likely require an authenticated flow.
        (IVault vault, IXERC20Lockbox lockbox, IXERC20 xToken, address receiver) =
            abi.decode(_data, (IVault, IXERC20Lockbox, IXERC20, address));

        // Withdraw vault shares from lockbox
        IERC20(_asset).approve(address(lockbox), _amount);
        lockbox.withdraw(_amount);

        // Convert vault shares to underlying and send it to receiver
        uint256 assetsOut = vault.redeem(_amount, receiver, address(this));

        return abi.encode(vault, lockbox, xToken, assetsOut);
    }

    function _forwardFunctionCall(bytes memory, bytes32, uint256, address) internal pure override returns (bool) {
        return true;
    }
}
