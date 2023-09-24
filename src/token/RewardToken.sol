// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "./IERC20Errors.sol";
import {IonPool} from "../IonPool.sol";
import {RoundedMath, RAY} from "../math/RoundedMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title RewardToken
 * @notice Heavily inspired by Aave's `AToken`
 */
contract RewardToken is Context, IERC20, IERC20Metadata, IERC20Errors {
    using RoundedMath for uint256;
    using SafeERC20 for IERC20;

    error InvalidBurnAmount();
    error InvalidMintAmount();
    error SelfTransfer(address addr);
    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);

    event Burn(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor);
    event Mint(address indexed user, uint256 amount, uint256 supplyFactor);
    event BalanceTransfer(address indexed from, address indexed to, uint256 value, uint256 index);

    // A user's true balance at any point will be the value in this mapping times the supplyFactor
    mapping(address account => uint256) _normalizedBalances; // [WAD]
    mapping(address account => mapping(address spender => uint256)) _allowances;
    mapping(address account => uint256) public nonces;

    bytes private constant EIP712_REVISION = bytes("1");
    bytes32 private constant EIP712_DOMAIN =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public immutable DOMAIN_SEPARATOR;

    address public immutable underlying;
    uint8 public immutable decimals;
    string public name;
    string public symbol;

    address public treasury;
    uint256 public normalizedTotalSupply; // [WAD]

    uint256 internal supplyFactor; // [RAY]

    constructor(address _underlying, address _treasury, uint8 decimals_, string memory name_, string memory symbol_) {
        underlying = _underlying;
        treasury = _treasury;
        decimals = decimals_;
        name = name_;
        symbol = symbol_;

        supplyFactor = RAY;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(EIP712_DOMAIN, keccak256(bytes(name_)), keccak256(EIP712_REVISION), block.chainid, address(this))
        );
    }

    function _burn(address user, address receiverOfUnderlying, uint256 amount) internal {
        uint256 _supplyFactor = supplyFactor;
        uint256 amountScaled = amount.roundedRayDiv(_supplyFactor);
        if (amountScaled == 0) revert InvalidBurnAmount();
        _burnNormalized(user, amountScaled);

        IERC20(underlying).safeTransfer(receiverOfUnderlying, amount);

        emit Transfer(user, address(0), amount);
        emit Burn(user, receiverOfUnderlying, amount, _supplyFactor);
    }

    function _burnNormalized(address account, uint256 amount) private {
        if (account == address(0)) revert ERC20InvalidSender(address(0));

        uint256 oldAccountBalance = _normalizedBalances[account];
        if (oldAccountBalance < amount) revert ERC20InsufficientBalance(account, oldAccountBalance, amount);
        // Underflow impossible
        unchecked {
            _normalizedBalances[account] = oldAccountBalance - amount;
        }

        normalizedTotalSupply -= amount;
    }

    function _mint(address user, uint256 amount) internal {
        uint256 _supplyFactor = supplyFactor;
        uint256 amountScaled = amount.roundedRayDiv(_supplyFactor);
        if (amountScaled == 0) revert InvalidMintAmount();
        _mintNormalized(user, amountScaled);

        IERC20(underlying).safeTransferFrom(_msgSender(), address(this), amount);

        emit Transfer(address(0), user, amount);
        emit Mint(user, amount, _supplyFactor);
    }

    function _mintNormalized(address account, uint256 amount) private {
        if (account == address(0)) revert ERC20InvalidReceiver(address(0));

        normalizedTotalSupply += amount;

        _normalizedBalances[account] += amount;
    }

    function _mintToTreasury(uint256 amount) internal {
        if (amount == 0) return;

        uint256 _supplyFactor = supplyFactor;
        address _treasury = treasury;

        // Compared to the normal mint, we don't check for rounding errors.
        // The amount to mint can easily be very small since it is a fraction of the interest accrued.
        // In that case, the treasury will experience a (very small) loss, but it
        // wont cause potentially valid transactions to fail.
        _mintNormalized(_treasury, amount.roundedRayDiv(_supplyFactor));

        emit Transfer(address(0), _treasury, amount);
        emit Mint(_treasury, amount, _supplyFactor);
    }

    function balanceOf(address user) public view returns (uint256) {
        return _normalizedBalances[user].roundedRayMul(supplyFactor);
    }

    function normalizedBalanceOf(address user) external view returns (uint256) {
        return _normalizedBalances[user];
    }

    function totalSupply() public view returns (uint256) {
        uint256 _normalizedTotalSupply = normalizedTotalSupply;

        if (_normalizedTotalSupply == 0) {
            return 0;
        }

        return _normalizedTotalSupply.roundedRayMul(supplyFactor);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 increaseAmount) external returns (bool) {
        _approve(_msgSender(), spender, allowance(_msgSender(), spender) + increaseAmount);
        return true;
    }

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

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

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
        _allowances[owner][spender] = newAllowance;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
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

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        if (from == to) revert SelfTransfer(from);

        uint256 _supplyFactor = supplyFactor;
        uint256 amountNormalized = amount.roundedRayDiv(_supplyFactor);

        uint256 oldSenderBalance = _normalizedBalances[from];
        if (oldSenderBalance < amountNormalized) {
            revert ERC20InsufficientBalance(from, oldSenderBalance, amountNormalized);
        }
        // Underflow impossible
        unchecked {
            _normalizedBalances[from] = oldSenderBalance - amountNormalized;
        }
        _normalizedBalances[to] += amountNormalized;

        emit BalanceTransfer(from, to, amountNormalized, _supplyFactor);
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

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
        unchecked {
            // It is important to do x++ and not ++x here.
            return nonces[owner]++;
        }
    }
}
