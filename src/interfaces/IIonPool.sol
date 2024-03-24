// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IIonPool {
    error AccessControlBadConfirmation();
    error AccessControlEnforcedDefaultAdminDelay(uint48 schedule);
    error AccessControlEnforcedDefaultAdminRules();
    error AccessControlInvalidDefaultAdmin(address defaultAdmin);
    error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);
    error AddressEmptyCode(address target);
    error AddressInsufficientBalance(address account);
    error ArithmeticError();
    error CeilingExceeded(uint256 newDebt, uint256 debtCeiling);
    error DepositSurpassesSupplyCap(uint256 depositAmount, uint256 supplyCap);
    error EnforcedPause();
    error ExpectedPause();
    error FailedInnerCall();
    error GemTransferWithoutConsent(uint8 ilkIndex, address user, address unconsentedOperator);
    error IlkAlreadyAdded(address ilkAddress);
    error IlkNotInitialized(uint256 ilkIndex);
    error InsufficientBalance(address account, uint256 balance, uint256 needed);
    error InvalidBurnAmount();
    error InvalidIlkAddress();
    error InvalidInitialization();
    error InvalidInterestRateModule(address invalidInterestRateModule);
    error InvalidMintAmount();
    error InvalidReceiver(address receiver);
    error InvalidSender(address sender);
    error InvalidTreasuryAddress();
    error InvalidUnderlyingAddress();
    error InvalidWhitelist();
    error MathOverflowedMulDiv();
    error MaxIlksReached();
    error NotInitializing();
    error NotScalingUp(uint256 from, uint256 to);
    error SafeCastOverflowedUintDowncast(uint8 bits, uint256 value);
    error SafeCastOverflowedUintToInt(uint256 value);
    error SafeERC20FailedOperation(address token);
    error TakingWethWithoutConsent(address payer, address unconsentedOperator);
    error UnsafePositionChange(uint256 newTotalDebtInVault, uint256 collateral, uint256 spot);
    error UnsafePositionChangeWithoutConsent(uint8 ilkIndex, address user, address unconsentedOperator);
    error UseOfCollateralWithoutConsent(uint8 ilkIndex, address depositor, address unconsentedOperator);
    error VaultCannotBeDusty(uint256 amountLeft, uint256 dust);

    event AddOperator(address indexed user, address indexed operator);
    event Borrow(
        uint8 indexed ilkIndex,
        address indexed user,
        address indexed recipient,
        uint256 amountOfNormalizedDebt,
        uint256 ilkRate,
        uint256 totalDebt
    );
    event ConfiscateVault(
        uint8 indexed ilkIndex,
        address indexed u,
        address v,
        address indexed w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    );
    event DefaultAdminDelayChangeCanceled();
    event DefaultAdminDelayChangeScheduled(uint48 newDelay, uint48 effectSchedule);
    event DefaultAdminTransferCanceled();
    event DefaultAdminTransferScheduled(address indexed newAdmin, uint48 acceptSchedule);
    event DepositCollateral(uint8 indexed ilkIndex, address indexed user, address indexed depositor, uint256 amount);
    event IlkDebtCeilingUpdated(uint8 indexed ilkIndex, uint256 newDebtCeiling);
    event IlkDustUpdated(uint8 indexed ilkIndex, uint256 newDust);
    event IlkInitialized(uint8 indexed ilkIndex, address indexed ilkAddress);
    event IlkSpotUpdated(uint8 indexed ilkIndex, address newSpot);
    event Initialized(uint64 version);
    event InterestRateModuleUpdated(address newModule);
    event MintAndBurnGem(uint8 indexed ilkIndex, address indexed usr, int256 wad);
    event MintToTreasury(address indexed treasury, uint256 amount, uint256 supplyFactor);
    event Paused(address account);
    event RemoveOperator(address indexed user, address indexed operator);
    event Repay(
        uint8 indexed ilkIndex,
        address indexed user,
        address indexed payer,
        uint256 amountOfNormalizedDebt,
        uint256 ilkRate,
        uint256 totalDebt
    );
    event RepayBadDebt(address indexed user, address indexed payer, uint256 rad);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Supply(
        address indexed user, address indexed underlyingFrom, uint256 amount, uint256 supplyFactor, uint256 newDebt
    );
    event SupplyCapUpdated(uint256 newSupplyCap);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event TransferGem(uint8 indexed ilkIndex, address indexed src, address indexed dst, uint256 wad);
    event TreasuryUpdate(address treasury);
    event Unpaused(address account);
    event WhitelistUpdated(address newWhitelist);
    event Withdraw(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor, uint256 newDebt);
    event WithdrawCollateral(uint8 indexed ilkIndex, address indexed user, address indexed recipient, uint256 amount);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
    function GEM_JOIN_ROLE() external view returns (bytes32);
    function ION() external view returns (bytes32);
    function LIQUIDATOR_ROLE() external view returns (bytes32);
    function PAUSE_ROLE() external view returns (bytes32);
    function acceptDefaultAdminTransfer() external;
    function accrueInterest() external returns (uint256 newTotalDebt);
    function addOperator(address operator) external;
    function addressContains(address ilk) external view returns (bool);
    function balanceOf(address user) external view returns (uint256);
    function beginDefaultAdminTransfer(address newAdmin) external;
    function borrow(
        uint8 ilkIndex,
        address user,
        address recipient,
        uint256 amountOfNormalizedDebt,
        bytes32[] memory proof
    )
        external;
    function calculateRewardAndDebtDistribution()
        external
        view
        returns (
            uint256 totalSupplyFactorIncrease,
            uint256 totalTreasuryMintAmount,
            uint104[] memory rateIncreases,
            uint256 totalDebtIncrease,
            uint48[] memory timestampIncreases
        );
    function calculateRewardAndDebtDistributionForIlk(uint8 ilkIndex)
        external
        view
        returns (uint104 newRateIncrease, uint48 timestampIncrease);
    function cancelDefaultAdminTransfer() external;
    function changeDefaultAdminDelay(uint48 newDelay) external;
    function collateral(uint8 ilkIndex, address user) external view returns (uint256);
    function confiscateVault(
        uint8 ilkIndex,
        address u,
        address v,
        address w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    )
        external;
    function debt() external view returns (uint256);
    function debtCeiling(uint8 ilkIndex) external view returns (uint256);
    function debtUnaccrued() external view returns (uint256);
    function decimals() external view returns (uint8);
    function defaultAdmin() external view returns (address);
    function defaultAdminDelay() external view returns (uint48);
    function defaultAdminDelayIncreaseWait() external view returns (uint48);
    function depositCollateral(
        uint8 ilkIndex,
        address user,
        address depositor,
        uint256 amount,
        bytes32[] memory proof
    )
        external;
    function dust(uint8 ilkIndex) external view returns (uint256);
    function gem(uint8 ilkIndex, address user) external view returns (uint256);
    function getCurrentBorrowRate(uint8 ilkIndex) external view returns (uint256 borrowRate, uint256 reserveFactor);
    function getIlkAddress(uint256 ilkIndex) external view returns (address);
    function getIlkIndex(address ilkAddress) external view returns (uint8);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function ilkCount() external view returns (uint256);
    function implementation() external view returns (address);
    function initialize(
        address _underlying,
        address _treasury,
        uint8 decimals_,
        string memory name_,
        string memory symbol_,
        address initialDefaultAdmin,
        address _interestRateModule,
        address _whitelist
    )
        external;
    function initializeIlk(address ilkAddress) external;
    function interestRateModule() external view returns (address);
    function isAllowed(address user, address operator) external view returns (bool);
    function isOperator(address user, address operator) external view returns (bool);
    function lastRateUpdate(uint8 ilkIndex) external view returns (uint256);
    function mintAndBurnGem(uint8 ilkIndex, address usr, int256 wad) external;
    function name() external view returns (string memory);
    function normalizedBalanceOf(address user) external view returns (uint256);
    function normalizedDebt(uint8 ilkIndex, address user) external view returns (uint256);
    function normalizedTotalSupply() external view returns (uint256);
    function normalizedTotalSupplyUnaccrued() external view returns (uint256);
    function owner() external view returns (address);
    function pause() external;
    function paused() external view returns (bool);
    function pendingDefaultAdmin() external view returns (address newAdmin, uint48 schedule);
    function pendingDefaultAdminDelay() external view returns (uint48 newDelay, uint48 schedule);
    function rate(uint8 ilkIndex) external view returns (uint256);
    function rateUnaccrued(uint8 ilkIndex) external view returns (uint256);
    function removeOperator(address operator) external;
    function renounceRole(bytes32 role, address account) external;
    function repay(uint8 ilkIndex, address user, address payer, uint256 amountOfNormalizedDebt) external;
    function repayBadDebt(address user, uint256 rad) external;
    function revokeRole(bytes32 role, address account) external;
    function rollbackDefaultAdminDelay() external;
    function spot(uint8 ilkIndex) external view returns (address);
    function supply(address user, uint256 amount, bytes32[] memory proof) external;
    function supplyFactor() external view returns (uint256);
    function supplyFactorUnaccrued() external view returns (uint256);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function symbol() external view returns (string memory);
    function totalNormalizedDebt(uint8 ilkIndex) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function totalSupplyUnaccrued() external view returns (uint256);
    function totalUnbackedDebt() external view returns (uint256);
    function transferGem(uint8 ilkIndex, address src, address dst, uint256 wad) external;
    function treasury() external view returns (address);
    function unbackedDebt(address user) external view returns (uint256);
    function underlying() external view returns (address);
    function unpause() external;
    function updateIlkDebtCeiling(uint8 ilkIndex, uint256 newCeiling) external;
    function updateIlkDust(uint8 ilkIndex, uint256 newDust) external;
    function updateIlkSpot(uint8 ilkIndex, address newSpot) external;
    function updateInterestRateModule(address _interestRateModule) external;
    function updateSupplyCap(uint256 newSupplyCap) external;
    function updateTreasury(address newTreasury) external;
    function updateWhitelist(address _whitelist) external;
    function vault(uint8 ilkIndex, address user) external view returns (uint256, uint256);
    function weth() external view returns (uint256);
    function whitelist() external view returns (address);
    function withdraw(address receiverOfUnderlying, uint256 amount) external;
    function withdrawCollateral(uint8 ilkIndex, address user, address recipient, uint256 amount) external;
}
