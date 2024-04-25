// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IVault {
    struct MarketAllocation {
        address pool;
        int256 assets;
    }

    error AddressEmptyCode(address target);
    error AddressInsufficientBalance(address account);
    error AllSupplyCapsReached();
    error AllocationCapOrSupplyCapExceeded();
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidSpender(address spender);
    error ERC4626ExceededMaxDeposit(address receiver, uint256 assets, uint256 max);
    error ERC4626ExceededMaxMint(address receiver, uint256 shares, uint256 max);
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);
    error FailedInnerCall();
    error InvalidIdleMarketRemovalNonZeroBalance();
    error InvalidMarketRemovalNonZeroSupply();
    error InvalidQueueContainsDuplicates();
    error InvalidQueueLength();
    error InvalidQueueMarketNotSupported();
    error InvalidSupportedMarkets();
    error IonPoolsArrayAndNewCapsArrayMustBeOfEqualLength();
    error MarketAlreadySupported();
    error MarketNotSupported();
    error MarketsAndAllocationCapLengthMustBeEqual();
    error MathOverflowedMulDiv();
    error NotEnoughLiquidityToWithdraw();
    error OwnableInvalidOwner(address owner);
    error OwnableUnauthorizedAccount(address account);
    error SafeERC20FailedOperation(address token);

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event FeeAccrued(uint256 feeShares, uint256 newTotalAssets);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ReallocateSupply(address indexed pool, uint256 assets);
    event ReallocateWithdraw(address indexed pool, uint256 assets);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event UpdateLastTotalAssets(uint256 lastTotalAssets, uint256 newLastTotalAssets);
    event UpdateSupplyQueue(address indexed caller, address newSupplyQueue);
    event UpdateWithdrawQueue(address indexed caller, address newWithdrawQueue);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function DECIMALS_OFFSET() external view returns (uint8);
    function acceptOwnership() external;
    function addSupportedMarkets(
        address marketsToAdd,
        uint256[] memory allocationCaps,
        address newSupplyQueue,
        address newWithdrawQueue
    )
        external;
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function asset() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function baseAsset() external view returns (address);
    function caps(address) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function decimals() external view returns (uint8);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function feePercentage() external view returns (uint256);
    function feeRecipient() external view returns (address);
    function getSupportedMarkets() external view returns (address[] memory);
    function ionLens() external view returns (address);
    function lastTotalAssets() external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256 assets);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewMint(uint256 shares) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function reallocate(MarketAllocation[] memory allocations) external;
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function removeSupportedMarkets(
        address marketsToRemove,
        address newSupplyQueue,
        address newWithdrawQueue
    )
        external;
    function renounceOwnership() external;
    function supplyQueue(uint256) external view returns (address);
    function symbol() external view returns (string memory);
    function totalAssets() external view returns (uint256 assets);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transferOwnership(address newOwner) external;
    function updateAllocationCaps(address ionPools, uint256[] memory newCaps) external;
    function updateSupplyQueue(address newSupplyQueue) external;
    function updateWithdrawQueue(address newWithdrawQueue) external;
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function withdrawQueue(uint256) external view returns (address);
}
