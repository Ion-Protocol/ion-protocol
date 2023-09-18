// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IonPool} from "../IonPool.sol";
import {RoundedMath} from "../math/RoundedMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Reward Token
 * @notice Heavily inspired by Aave's `AToken`
 */
contract RewardToken is Context, IERC20, IERC20Metadata {
    using RoundedMath for uint256;
    using SafeERC20 for IERC20;

    error InvalidBurnAmount();
    error BurnAmountExceedsBalance(uint256 availableBalance, uint256 burnAmount);
    error InvalidMintAmount();
    error InvalidApprovalOwner(address owner);
    error InvalidApprovalSpender(address spender);
    error InsufficientAllowance(address spender, uint256 currentAllowance, uint256 attemptedSpend);
    error InvalidTransferFrom(address from);
    error InvalidTransferTo(address to);
    error TransferAmountExceedsBalance(address spender, uint256 balance, uint256 attemptedSpend);
    error SelfTransfer(address addr);

    event Burn(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor);
    event Mint(address indexed user, uint256 amount, uint256 supplyFactor);
    event BalanceTransfer(address indexed from, address indexed to, uint256 value, uint256 index);

    // A user's true balance at any point will be the value in this mapping times the supplyFactor
    mapping(address account => uint256) _normalizedBalances;
    mapping(address account => mapping(address spender => uint256)) _allowances;

    address public immutable underlying;
    address public immutable treasury;
    uint8 public immutable decimals;

    uint256 public normalizedTotalSupply;
    string public name;
    string public symbol;

    uint256 internal supplyFactor;

    constructor(address _underlying, address _treasury, uint8 decimals_, string memory name_, string memory symbol_) {
        underlying = _underlying;
        treasury = _treasury;
        decimals = decimals_;
        name = name_;
        symbol = symbol_;
        supplyFactor = 1e18;
    }

    function _burn(address user, address receiverOfUnderlying, uint256 amount) internal {
        uint256 amountScaled = amount.roundedDiv(supplyFactor);
        if (amountScaled == 0) revert InvalidBurnAmount();
        _burnNormalized(user, amountScaled);

        IERC20(underlying).safeTransfer(receiverOfUnderlying, amount);

        emit Transfer(user, address(0), amount);
        emit Burn(user, receiverOfUnderlying, amount, supplyFactor);
    }

    function _burnNormalized(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        normalizedTotalSupply -= amount;

        uint256 oldAccountBalance = _normalizedBalances[account];
        if (oldAccountBalance < amount) revert BurnAmountExceedsBalance(oldAccountBalance, amount);
        _normalizedBalances[account] = oldAccountBalance - amount;
    }

    function _mint(address user, uint256 amount) internal {
        uint256 _supplyFactor = supplyFactor;
        uint256 amountScaled = amount.roundedDiv(_supplyFactor);
        if (amountScaled == 0) revert InvalidMintAmount();
        _mintNormalized(user, amountScaled);
        
        IERC20(underlying).safeTransferFrom(_msgSender(), address(this), amount);

        emit Transfer(address(0), user, amount);
        emit Mint(user, amount, _supplyFactor);
    }

    function _mintNormalized(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        normalizedTotalSupply += amount;

        _normalizedBalances[account] += amount;
    }

    function _mintToTreasury(uint256 amount, uint256 index) internal {
        if (amount == 0) {
            return;
        }

        address _treasury = treasury;

        // Compared to the normal mint, we don't check for rounding errors.
        // The amount to mint can easily be very small since it is a fraction of the interest accrued.
        // In that case, the treasury will experience a (very small) loss, but it
        // wont cause potentially valid transactions to fail.
        _mintNormalized(_treasury, amount.roundedDiv(index));

        emit Transfer(address(0), _treasury, amount);
        emit Mint(_treasury, amount, index);
    }

    function balanceOf(address user) public view returns (uint256) {
        return _normalizedBalances[user].roundedMul(supplyFactor);
    }

    function normalizedBalanceOf(address user) external view returns (uint256) {
        return _normalizedBalances[user];
    }

    function totalSupply() public view returns (uint256) {
        uint256 _normalizedTotalSupply = normalizedTotalSupply;

        if (_normalizedTotalSupply == 0) {
            return 0;
        }

        return _normalizedTotalSupply.roundedMul(supplyFactor);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) revert InvalidApprovalOwner(address(0));
        if (spender == address(0)) revert InvalidApprovalSpender(address(0));

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < amount) {
            revert InsufficientAllowance(spender, currentAllowance, amount);
        }
        uint256 newAllowance;
        // Underflow impossible
        unchecked {
            newAllowance = currentAllowance - amount;
        }
        _allowances[owner][spender] = newAllowance;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transferUnderlyingTo(address target, uint256 amount) internal returns (uint256) {
        IERC20(underlying).safeTransfer(target, amount);
        return amount;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(_msgSender(), to, amount);
        emit Transfer(_msgSender(), to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);

        emit Transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0)) revert InvalidTransferFrom(address(0));
        if (to == address(0)) revert InvalidTransferTo(address(0));
        if (from == to) revert SelfTransfer(from);

        uint256 _supplyFactor = supplyFactor;
        uint256 amountNormalized = amount.roundedDiv(_supplyFactor);

        uint256 oldSenderBalance = _normalizedBalances[from];
        if (oldSenderBalance < amountNormalized) {
            revert TransferAmountExceedsBalance(from, oldSenderBalance, amountNormalized);
        }
        // Underflow impossible
        unchecked {
            _normalizedBalances[from] = oldSenderBalance - amountNormalized;
        }
        _normalizedBalances[to] += amountNormalized;

        emit BalanceTransfer(from, to, amountNormalized, _supplyFactor);
    }
}
