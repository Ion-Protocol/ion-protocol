// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Errors } from "./IERC20Errors.sol";
import { RoundedMath, RAY } from "../math/RoundedMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

/**
 * @title RewardToken
 * @notice Heavily inspired by Aave's `AToken`
 */
contract RewardToken is ContextUpgradeable, IERC20, IERC20Metadata, IERC20Errors {
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

    /**
     * @dev Cannot transfer the token to address `self`
     */
    error SelfTransfer(address self);

    /**
     * @dev Signature cannot be submitted after `deadline` has passed. Designed to
     * mitigate replay attacks.
     */
    error ERC2612ExpiredSignature(uint256 deadline);

    /**
     * @dev `signer` does not match the `owner` of the tokens. `owner` did not approve.
     */
    error ERC2612InvalidSigner(address signer, address owner);

    error InvalidUnderlyingAddress();
    error InvalidTreasuryAddress();

    /**
     * @dev Emitted when `RewardToken`s are burned by `user` in exchange for `amount` underlying tokens redeemed to
     * `target`. `supplyFactor` is the  supply factor at the time.
     */
    event Burn(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor);

    /**
     * @dev Emitted when `RewardToken`s are minted by `user` in exchange for `amount` underlying tokens. `supplyFactor`
     * is the  supply factor at the time.
     */
    event Mint(address indexed user, uint256 amount, uint256 supplyFactor);

    /**
     * @dev Emitted when `amount` of `RewardToken`s are transferred from `from` to `to`. `supplyFactor` is the  supply
     * factor at the time.
     */
    event BalanceTransfer(address indexed from, address indexed to, uint256 amount, uint256 supplyFactor);

    bytes private constant EIP712_REVISION = bytes("1");
    bytes32 private constant EIP712_DOMAIN =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public DOMAIN_SEPARATOR;

    struct RewardTokenStorage {
        IERC20 underlying;
        uint8 decimals;
        // A user's true balance at any point will be the value in this mapping times the supplyFactor
        mapping(address account => uint256) _normalizedBalances; // [WAD]
        mapping(address account => mapping(address spender => uint256)) _allowances;
        mapping(address account => uint256) nonces;
        string name;
        string symbol;
        address treasury;
        uint256 normalizedTotalSupply; // [WAD]
        uint256 supplyFactor; // [RAY]
    }

    // keccak256(abi.encode(uint256(keccak256("ion.storage.RewardToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RewardTokenStorageLocation =
        0xe67839269f312704c9976b7a04f41bb97402897b34aca7a5cf2bb59c89583000;

    function _getRewardTokenStorage() private pure returns (RewardTokenStorage storage $) {
        assembly {
            $.slot := RewardTokenStorageLocation
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

        RewardTokenStorage storage $ = _getRewardTokenStorage();

        $.underlying = IERC20(_underlying);
        $.treasury = _treasury;
        $.decimals = decimals_;
        $.name = name_;
        $.symbol = symbol_;

        $.supplyFactor = RAY;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(EIP712_DOMAIN, keccak256(bytes(name_)), keccak256(EIP712_REVISION), block.chainid, address(this))
        );
    }

    // TODO: Do rounding in protocol's favor
    /**
     *
     * @param user to burn tokens from
     * @param receiverOfUnderlying to send underlying tokens to
     * @param amount to burn
     */
    function _burn(address user, address receiverOfUnderlying, uint256 amount) internal {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

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
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        if (account == address(0)) revert ERC20InvalidSender(address(0));

        uint256 oldAccountBalance = $._normalizedBalances[account];
        if (oldAccountBalance < amount) revert ERC20InsufficientBalance(account, oldAccountBalance, amount);
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
        RewardTokenStorage storage $ = _getRewardTokenStorage();

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
        if (account == address(0)) revert ERC20InvalidReceiver(address(0));

        RewardTokenStorage storage $ = _getRewardTokenStorage();

        $.normalizedTotalSupply += amount;

        $._normalizedBalances[account] += amount;
    }

    /**
     * @dev This function does not perform any rounding checks.
     * @param amount of tokens to mint to treasury
     */
    function _mintToTreasury(uint256 amount) internal {
        if (amount == 0) return;

        RewardTokenStorage storage $ = _getRewardTokenStorage();

        uint256 _supplyFactor = $.supplyFactor;
        address _treasury = $.treasury;

        // Compared to the normal mint, we don't check for rounding errors.
        // The amount to mint can easily be very small since it is a fraction of the interest accrued.
        // In that case, the treasury will experience a (very small) loss, but it
        // wont cause potentially valid transactions to fail.
        _mintNormalized(_treasury, amount.roundedRayDiv(_supplyFactor));

        emit Transfer(address(0), _treasury, amount);
        emit Mint(_treasury, amount, _supplyFactor);
    }

    function name() public view returns (string memory) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        return $.name;
    }

    function symbol() public view returns (string memory) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        return $.symbol;
    }

    /**
     * @dev Current token balance
     * @param user to get balance of
     */
    function balanceOf(address user) public view returns (uint256) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        return $._normalizedBalances[user].roundedRayMul($.supplyFactor);
    }

    /**
     * @dev Accounting is done in normalized balances
     * @param user to get normalized balance of
     */
    function normalizedBalanceOf(address user) external view returns (uint256) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        return $._normalizedBalances[user];
    }

    /**
     * @dev Current total supply
     */
    function totalSupply() public view returns (uint256) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        uint256 _normalizedTotalSupply = $.normalizedTotalSupply;

        if (_normalizedTotalSupply == 0) {
            return 0;
        }

        return _normalizedTotalSupply.roundedRayMul($.supplyFactor);
    }

    function normalizedTotalSupply() public view returns (uint256) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        return $.normalizedTotalSupply;
    }

    function decimals() public view returns (uint8) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        return $.decimals;
    }

    /**
     *
     * @param spender to approve
     * @param amount to approve
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev Front-running more likely to maintain user intent
     * @param spender to increase allowance of
     * @param increaseAmount to increase by
     */
    function increaseAllowance(address spender, uint256 increaseAmount) external returns (bool) {
        _approve(_msgSender(), spender, allowance(_msgSender(), spender) + increaseAmount);
        return true;
    }

    /**
     *
     * @param spender to decrease allowance of
     * @param decreaseAmount to decrease by
     */
    function decreaseAllowance(address spender, uint256 decreaseAmount) public virtual returns (bool) {
        uint256 currentAllowance = allowance(_msgSender(), spender);

        if (currentAllowance < decreaseAmount) {
            revert ERC20InsufficientAllowance(spender, currentAllowance, decreaseAmount);
        }

        uint256 newAllowance;
        // Underflow impossible
        unchecked {
            newAllowance = currentAllowance - decreaseAmount;
        }

        _approve(_msgSender(), spender, newAllowance);
        return true;
    }

    /**
     *
     * @param owner of tokens
     * @param spender of tokens
     * @param amount to approve
     */
    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));

        RewardTokenStorage storage $ = _getRewardTokenStorage();

        $._allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Spends allowance
     */
    function _spendAllowance(address owner, address spender, uint256 amount) private {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < amount) {
            revert ERC20InsufficientAllowance(spender, currentAllowance, amount);
        }
        uint256 newAllowance;
        // Underflow impossible
        unchecked {
            newAllowance = currentAllowance - amount;
        }

        RewardTokenStorage storage $ = _getRewardTokenStorage();

        $._allowances[owner][spender] = newAllowance;
    }

    /**
     * @dev Returns current allowance
     * @param owner of tokens
     * @param spender of tokens
     */
    function allowance(address owner, address spender) public view returns (uint256) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        return $._allowances[owner][spender];
    }

    /**
     * @dev Can only be called by owner of the tokens
     * @param to transfer to
     * @param amount to transfer
     */
    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(_msgSender(), to, amount);
        emit Transfer(_msgSender(), to, amount);
        return true;
    }

    /**
     * @dev For use with `approve()`
     * @param from to transfer from
     * @param to to transfer to
     * @param amount to transfer
     */
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);

        emit Transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        if (from == to) revert SelfTransfer(from);

        RewardTokenStorage storage $ = _getRewardTokenStorage();

        uint256 _supplyFactor = $.supplyFactor;
        uint256 amountNormalized = amount.roundedRayDiv(_supplyFactor);

        uint256 oldSenderBalance = $._normalizedBalances[from];
        if (oldSenderBalance < amountNormalized) {
            revert ERC20InsufficientBalance(from, oldSenderBalance, amountNormalized);
        }
        // Underflow impossible
        unchecked {
            $._normalizedBalances[from] = oldSenderBalance - amountNormalized;
        }
        $._normalizedBalances[to] += amountNormalized;

        emit BalanceTransfer(from, to, amountNormalized, _supplyFactor);
    }

    /**
     * @dev implements the permit function as for
     * https://github.com/ethereum/EIPs/blob/8a34d644aacf0f9f8f00815307fd7dd5da07655f/EIPS/eip-2612.md
     * @param owner The owner of the funds
     * @param spender The spender
     * @param value The amount
     * @param deadline The deadline timestamp, type(uint256).max for max deadline
     * @param v Signature param
     * @param s Signature param
     * @param r Signature param
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        public
        virtual
    {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != owner) {
            revert ERC2612InvalidSigner(signer, owner);
        }

        _approve(owner, spender, value);
    }

    /**
     * @dev Consumes a nonce.
     *
     * Returns the current value and increments nonce.
     */
    function _useNonce(address owner) internal virtual returns (uint256) {
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        unchecked {
            // It is important to do x++ and not ++x here.
            return $.nonces[owner]++;
        }
    }

    function _setSupplyFactor(uint256 newSupplyFactor) internal {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        $.supplyFactor = newSupplyFactor;
    }

    function getSupplyFactor() public view returns (uint256) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        return $.supplyFactor;
    }

    function getUnderlying() public view returns (IERC20) {
        RewardTokenStorage storage $ = _getRewardTokenStorage();

        return $.underlying;
    }
}
