// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import { WadRayMath, RAY } from "../libraries/math/WadRayMath.sol";

import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import { AccessControlDefaultAdminRulesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title RewardModule
 * @notice The supply-side reward accounting portion of the protocol. A lender's
 * balance is measured in two parts: a static balance and a dynamic "supply
 * factor". Their true balance is the product of the two values. The dynamic
 * portion is then able to be used to distribute interest accrued to the lender.
 *
 * @custom:security-contact security@molecularlabs.io
 */
abstract contract RewardModule is ContextUpgradeable, AccessControlDefaultAdminRulesUpgradeable {
    using WadRayMath for uint256;
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
     * @param account Address whose token balance is insufficient.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     */
    error InsufficientBalance(address account, uint256 balance, uint256 needed);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    event MintToTreasury(address indexed treasury, uint256 amount, uint256 supplyFactor);

    event TreasuryUpdate(address treasury);

    /// @custom:storage-location erc7201:ion.storage.RewardModule
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

    bytes32 public constant ION = keccak256("ION");

    // keccak256(abi.encode(uint256(keccak256("ion.storage.RewardModule")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 private constant RewardModuleStorageLocation =
        0xdb3a0d63a7808d7d0422c40bb62354f42bff7602a547c329c1453dbcbeef4900;

    function _getRewardModuleStorage() private pure returns (RewardModuleStorage storage $) {
        assembly {
            $.slot := RewardModuleStorageLocation
        }
    }

    function _initialize(
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

        emit TreasuryUpdate(_treasury);
    }

    /**
     *
     * @param user to burn tokens from
     * @param receiverOfUnderlying to send underlying tokens to
     * @param amount to burn
     */
    function _burn(address user, address receiverOfUnderlying, uint256 amount) internal returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();

        uint256 _supplyFactor = $.supplyFactor;
        uint256 amountScaled = amount.rayDivUp(_supplyFactor);

        if (amountScaled == 0) revert InvalidBurnAmount();
        _burnNormalized(user, amountScaled);

        $.underlying.safeTransfer(receiverOfUnderlying, amount);

        emit Transfer(user, address(0), amount);

        return _supplyFactor;
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
     * @param user to mint tokens to
     * @param senderOfUnderlying address to transfer underlying tokens from
     * @param amount of reward tokens to mint
     */
    function _mint(address user, address senderOfUnderlying, uint256 amount) internal returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();

        uint256 _supplyFactor = $.supplyFactor;
        uint256 amountScaled = amount.rayDivDown(_supplyFactor); // [WAD] * [RAY] / [RAY] = [WAD]
        if (amountScaled == 0) revert InvalidMintAmount();
        _mintNormalized(user, amountScaled);

        $.underlying.safeTransferFrom(senderOfUnderlying, address(this), amount);

        emit Transfer(address(0), user, amount);

        return _supplyFactor;
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
        emit MintToTreasury(_treasury, amount, _supplyFactor);
    }

    function _setSupplyFactor(uint256 newSupplyFactor) internal {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        $.supplyFactor = newSupplyFactor;
    }

    /**
     * @dev Updates the treasury address
     * @param newTreasury address of new treasury
     */
    function updateTreasury(address newTreasury) external onlyRole(ION) {
        if (newTreasury == address(0)) revert InvalidTreasuryAddress();

        RewardModuleStorage storage $ = _getRewardModuleStorage();
        $.treasury = newTreasury;

        emit TreasuryUpdate(newTreasury);
    }

    // --- Getters ---

    /**
     * @dev Address of underlying asset
     */
    function underlying() public view returns (IERC20) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.underlying;
    }

    /**
     * @dev Decimals of the position asset
     */
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

        (uint256 totalSupplyFactorIncrease,,,,) = calculateRewardAndDebtDistribution();

        return $._normalizedBalances[user].rayMulDown($.supplyFactor + totalSupplyFactorIncrease);
    }

    /**
     * @dev Accounting is done in normalized balances
     * @param user to get normalized balance of
     */
    function normalizedBalanceOf(address user) external view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $._normalizedBalances[user];
    }

    /**
     * @dev Name of the position asset
     */
    function name() public view returns (string memory) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.name;
    }

    /**
     * @dev Symbol of the position asset
     */
    function symbol() public view returns (string memory) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.symbol;
    }

    /**
     * @dev Current treasury address
     */
    function treasury() public view returns (address) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.treasury;
    }

    function totalSupplyUnaccrued() public view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();

        uint256 _normalizedTotalSupply = $.normalizedTotalSupply;

        if (_normalizedTotalSupply == 0) {
            return 0;
        }

        return _normalizedTotalSupply.rayMulDown($.supplyFactor);
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

        (uint256 totalSupplyFactorIncrease,,,,) = calculateRewardAndDebtDistribution();

        return _normalizedTotalSupply.rayMulDown($.supplyFactor + totalSupplyFactorIncrease);
    }

    function normalizedTotalSupplyUnaccrued() public view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.normalizedTotalSupply;
    }

    /**
     * @dev Current normalized total supply
     */
    function normalizedTotalSupply() public view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();

        (uint256 totalSupplyFactorIncrease, uint256 totalTreasuryMintAmount,,,) = calculateRewardAndDebtDistribution();

        uint256 normalizedTreasuryMintAmount =
            totalTreasuryMintAmount.rayDivDown($.supplyFactor + totalSupplyFactorIncrease);

        return $.normalizedTotalSupply + normalizedTreasuryMintAmount;
    }

    function supplyFactorUnaccrued() public view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();
        return $.supplyFactor;
    }

    /**
     * @dev Current supply factor
     */
    function supplyFactor() public view returns (uint256) {
        RewardModuleStorage storage $ = _getRewardModuleStorage();

        (uint256 totalSupplyFactorIncrease,,,,) = calculateRewardAndDebtDistribution();

        return $.supplyFactor + totalSupplyFactorIncrease;
    }

    function calculateRewardAndDebtDistribution()
        public
        view
        virtual
        returns (
            uint256 totalSupplyFactorIncrease,
            uint256 totalTreasuryMintAmount,
            uint104[] memory rateIncreases,
            uint256 totalDebtIncrease,
            uint48[] memory timestampIncreases
        );
}
