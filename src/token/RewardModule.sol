// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Errors } from "./IERC20Errors.sol";
import { RoundedMath, RAY } from "../libraries/math/RoundedMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

/**
 * @title RewardModule
 * @notice Heavily inspired by Aave's `AToken` but without tokenization.
 */
abstract contract RewardModule is ContextUpgradeable {
    using RoundedMath for uint256;
    using SafeERC20 for IERC20;

    /**
     * @dev Cannot burn amount whose normalized value is less than zero.
     */
    error InvalidBurnAmount();

    /**
     * @dev Cannot mint amount whose normalized value is less than zero.
     */
    error InvalidMintAmount();

    error InvalidUnderlyingAddress();
    error InvalidTreasuryAddress();

    /**
     * @dev Indicates a failure with the token `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     */
    error InvalidSender(address sender);

    /**
     * @dev Indicates a failure with the token `receiver`. Used in transfers.
     * @param receiver Address to which tokens are being transferred.
     */
    error InvalidReceiver(address receiver);

    /**
     * @dev Indicates an error related to the current `balance` of a `sender`. Used in transfers.
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when ``s are burned by `user` in exchange for `amount` underlying tokens redeemed to
     * `target`. `supplyFactor` is the  supply factor at the time.
     */
    event Burn(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor);

    /**
     * @dev Emitted when `RewardToken`s are minted by `user` in exchange for `amount` underlying tokens. `supplyFactor`
     * is the  supply factor at the time.
     */
    event Mint(address indexed user, uint256 amount, uint256 supplyFactor);

    struct RewardModuleStorage {
        IERC20 underlying;
        uint8 decimals;
        // A user's true balance at any point will be the value in this mapping times the supplyFactor
        string name;
        string symbol;
        address treasury;
        uint256 normalizedTotalSupply; // [WAD]
        uint256 supplyFactor; // [RAY]
        mapping(address account => uint256) _normalizedBalances; // [WAD]
    }

    // keccak256(abi.encode(uint256(keccak256("ion.storage.RewardModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RewardModuleStorageLocation =
        0xdb3a0d63a7808d7d0422c40bb62354f42bff7602a547c329c1453dbcbeef4900;

    function _getRewardModuleStorage() private pure returns (RewardModuleStorage storage $) {
        assembly {
            $.slot := RewardModuleStorageLocation
        }
    }

    function initialize(
        address _underlying,
        address _treasury,
        uint8 decimals_,
        string memory name_,
        string memory symbol_
    )
        internal
        onlyInitializing
    {
        if (_underlying == address(0)) revert InvalidUnderlyingAddress();
        if (_treasury == address(0)) revert InvalidTreasuryAddress();

        RewardModuleStorage storage $ = _getRewardModuleStorage();

        $.underlying = IERC20(_underlying);
        $.treasury = _treasury;
        $.decimals = decimals_;
        $.name = name_;
        $.symbol = symbol_;
        $.supplyFactor = RAY;
    }

    /**
     *
     * @param user to burn tokens from
     * @param receiverOfUnderlying to send underlying tokens to
     * @param amount to burn
     */
    function _burn(address user, address receiverOfUnderlying, uint256 amount) internal {
        RewardModuleStorage storage $ = _getRewardModuleStorage();

        uint256 _supplyFactor = $.supplyFactor;
        uint256 amountScaled = amount.rayDivUp(_supplyFactor);
        if (amountScaled == 0) revert InvalidBurnAmount();
        _burnNormalized(user, amountScaled);

        $.underlying.safeTransfer(receiverOfUnderlying, amount);

        emit Transfer(user, address(0), amount);
        emit Burn(user, receiverOfUnderlying, amount, _supplyFactor);
    }

    /**
     *
     * @param account to decrease balance of
     * @param amount of normalized tokens to burn
     */
    function _burnNormalized(address account, uint256 amount) private {
        RewardModuleStorage storage $ = _getRewardModuleStorage();

        if (account == address(0)) revert InvalidSender(address(0));

        uint256 oldAccountBalance = $._normalizedBalances[account];
        if (oldAccountBalance < amount) revert InsufficientBalance(account, oldAccountBalance, amount);
        // Underflow impossible
        unchecked {
            $._normalizedBalances[account] = oldAccountBalance - amount;
        }

        $.normalizedTotalSupply -= amount;
    }

    /**
     *
     * @param user to mint tokens to and transfer underlying tokens from
     * @param amount of reward tokens to mint
     */
    function _mint(address user, uint256 amount) internal {
        RewardModuleStorage storage $ = _getRewardModuleStorage();

        uint256 _supplyFactor = $.supplyFactor;
        uint256 amountScaled = amount.rayDivDown(_supplyFactor); // [WAD] * [RAY] / [RAY] = [WAD]
        if (amountScaled == 0) revert InvalidMintAmount();
        _mintNormalized(user, amountScaled);

        $.underlying.safeTransferFrom(_msgSender(), address(this), amount);

        emit Transfer(address(0), user, amount);
        emit Mint(user, amount, _supplyFactor);
    }

    /**
     *
     * @param account to increase balance of
     * @param amount of normalized tokens to mint
     */
    function _mintNormalized(address account, uint256 amount) private {
        if (account == address(0)) revert InvalidReceiver(address(0));

        RewardModuleStorage storage $ = _getRewardModuleStorage();

        $.normalizedTotalSupply += amount;

        $._normalizedBalances[account] += amount;
    }

    /**
     * @dev This function does not perform any rounding checks.
     * @param amount of tokens to mint to treasury
     */
    function _mintToTreasury(uint256 amount) internal {
        if (amount == 0) return;

        RewardModuleStorage storage $ = _getRewardModuleStorage();

        uint256 _supplyFactor = $.supplyFactor;
        address _treasury = $.treasury;

        // Compared to the normal mint, we don't check for rounding errors.
        // The amount to mint can easily be very small since it is a fraction of the interest accrued.
        // In that case, the treasury will experience a (very small) loss, but it
        // wont cause potentially valid transactions to fail.
        _mintNormalized(_treasury, amount.rayDivDown(_supplyFactor));

        emit Transfer(address(0), _treasury, amount);
        emit Mint(_treasury, amount, _supplyFactor);
    }

    function _setSupplyFactor(uint256 newSupplyFactor) internal {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        $.supplyFactor = newSupplyFactor;
    }

    // --- Getters ---

    function underlying() public view returns (IERC20) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.underlying;
    }

    function decimals() public view returns (uint8) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.decimals;
    }

    /**
     * @dev Current token balance
     * @param user to get balance of
     */
    function balanceOf(address user) public view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $._normalizedBalances[user].rayMulDown($.supplyFactor);
    }

    /**
     * @dev Accounting is done in normalized balances
     * @param user to get normalized balance of
     */
    function normalizedBalanceOf(address user) external view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $._normalizedBalances[user];
    }

    function name() public view returns (string memory) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.name;
    }

    function symbol() public view returns (string memory) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.symbol;
    }

    function treasury() public view returns (address) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.treasury;
    }

    /**
     * @dev Current total supply
     */
    function totalSupply() public view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();

        uint256 _normalizedTotalSupply = $.normalizedTotalSupply;

        if (_normalizedTotalSupply == 0) {
            return 0;
        }

        return _normalizedTotalSupply.rayMulDown($.supplyFactor);
    }

    function normalizedTotalSupply() public view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.normalizedTotalSupply;
    }

    function supplyFactor() public view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.supplyFactor;
    }
}
