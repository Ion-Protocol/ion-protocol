// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IVault {
    struct MarketAllocation {
        address pool;
        int256 assets;
    }

    error AccessControlBadConfirmation();
    error AccessControlEnforcedDefaultAdminDelay(uint48 schedule);
    error AccessControlEnforcedDefaultAdminRules();
    error AccessControlInvalidDefaultAdmin(address defaultAdmin);
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error AddressEmptyCode(address target);
    error AddressInsufficientBalance(address account);
    error AllSupplyCapsReached();
    error AllocationCapExceeded();
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
    error InvalidReallocation();
    error InvalidSupportedMarkets();
    error IonPoolsArrayAndNewCapsArrayMustBeOfEqualLength();
    error MarketAlreadySupported();
    error MarketNotSupported();
    error MarketsAndAllocationCapLengthMustBeEqual();
    error MathOverflowedMulDiv();
    error NotEnoughLiquidityToWithdraw();
    error ReentrancyGuardReentrantCall();
    error SafeCastOverflowedUintDowncast(uint8 bits, uint256 value);
    error SafeERC20FailedOperation(address token);

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DefaultAdminDelayChangeCanceled();
    event DefaultAdminDelayChangeScheduled(uint48 newDelay, uint48 effectSchedule);
    event DefaultAdminTransferCanceled();
    event DefaultAdminTransferScheduled(address indexed newAdmin, uint48 acceptSchedule);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event FeeAccrued(uint256 feeShares, uint256 newTotalAssets);
    event ReallocateSupply(address indexed pool, uint256 assets);
    event ReallocateWithdraw(address indexed pool, uint256 assets);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event UpdateLastTotalAssets(uint256 lastTotalAssets, uint256 newLastTotalAssets);
    event UpdateSupplyQueue(address indexed caller, address newSupplyQueue);
    event UpdateWithdrawQueue(address indexed caller, address newWithdrawQueue);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function ALLOCATOR_ROLE() external view returns (bytes32);
    function DECIMALS_OFFSET() external view returns (uint8);
    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function OWNER_ROLE() external view returns (bytes32);
    function acceptDefaultAdminTransfer() external;
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
    function beginDefaultAdminTransfer(address newAdmin) external;
    function cancelDefaultAdminTransfer() external;
    function caps(address) external view returns (uint256);
    function changeDefaultAdminDelay(uint48 newDelay) external;
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function decimals() external view returns (uint8);
    function defaultAdmin() external view returns (address);
    function defaultAdminDelay() external view returns (uint48);
    function defaultAdminDelayIncreaseWait() external view returns (uint48);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function feePercentage() external view returns (uint256);
    function feeRecipient() external view returns (address);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function getSupportedMarkets() external view returns (address[] memory);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function ionLens() external view returns (address);
    function lastTotalAssets() external view returns (uint256);
    function maxDeposit(address) external view returns (uint256);
    function maxMint(address) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
    function maxWithdraw(address owner) external view returns (uint256 assets);
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
    function multicall(bytes[] memory data) external returns (bytes[] memory results);
    function name() external view returns (string memory);
    function owner() external view returns (address);
    function pendingDefaultAdmin() external view returns (address newAdmin, uint48 schedule);
    function pendingDefaultAdminDelay() external view returns (uint48 newDelay, uint48 schedule);
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
    function renounceRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function rollbackDefaultAdminDelay() external;
    function supplyQueue(uint256) external view returns (address);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function symbol() external view returns (string memory);
    function totalAssets() external view returns (uint256 assets);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function updateAllocationCaps(address ionPools, uint256[] memory newCaps) external;
    function updateFeePercentage(uint256 _feePercentage) external;
    function updateFeeRecipient(address _feeRecipient) external;
    function updateSupplyQueue(address newSupplyQueue) external;
    function updateWithdrawQueue(address newWithdrawQueue) external;
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);
    function withdrawQueue(uint256) external view returns (address);
}
