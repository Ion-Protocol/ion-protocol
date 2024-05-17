// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IConnext } from "../interfaces/IConnext.sol";
import { IVault } from "../interfaces/IVault.sol";
import { IXERC20 } from "../interfaces/IXERC20.sol";
import { IXERC20Lockbox } from "../interfaces/IXERC20Lockbox.sol";

contract L1BasicMint {
    error InvalidVault(IVault vault, IXERC20Lockbox lockbox);
    error InvalidXToken(IXERC20 xToken, IXERC20Lockbox lockbox);

    using SafeERC20 for IERC20;

    // Connext address on this domain
    IConnext public immutable CONNEXT;

    constructor(IConnext _connext) {
        CONNEXT = _connext;
    }

    /**
     * @notice Deposit funds into the vault and receive the vault's share token
     * on L2.
     *
     * @param vault The vault to deposit into.
     * @param lockbox The lockbox to deposit into. The ERC20 of the lockbox
     * should be the vault token.
     * @param xToken The xToken to mint on the L1. This should be the xToken in
     * the lockbox as well.
     * @param amountOfBase The amount of base asset to deposit.
     * @param destination The destination domain ID (this can be different from
     * the chain id).
     * @param to The address to receive the bridged token on the destination.
     * @param slippage TODO: See if this is relevant for slowpath
     */
    function depositAndXCall(
        IVault vault,
        IXERC20Lockbox lockbox,
        IXERC20 xToken,
        uint256 amountOfBase,
        uint32 destination,
        address to,
        uint256 slippage
    )
        external
        payable
    {
        address baseAsset = vault.BASE_ASSET();
        if (address(lockbox.ERC20()) != address(vault)) revert InvalidVault(vault, lockbox);
        if (lockbox.XERC20() != xToken) revert InvalidXToken(xToken, lockbox);

        // Convert underlying to vault shares
        IERC20 _baseAsset = IERC20(baseAsset);
        _baseAsset.safeTransferFrom(msg.sender, address(this), amountOfBase);
        _baseAsset.forceApprove(address(vault), amountOfBase);
        uint256 shares = vault.deposit(amountOfBase, address(this));

        // Convert vault shares to xToken
        vault.approve(address(lockbox), shares);
        lockbox.deposit(shares);

        // Bridge xToken to L2
        xToken.approve(address(CONNEXT), shares);
        CONNEXT.xcall{ value: msg.value }(destination, to, address(xToken), address(0), shares, slippage, hex"");
    }
}
