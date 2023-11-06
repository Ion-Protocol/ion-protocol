// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IIonPoolEvents {
    event AddOperator(address indexed from, address indexed to);
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
    event IlkDebtCeilingUpdated(uint256 newDebtCeiling);
    event IlkDustUpdated(uint256 newDust);
    event IlkInitialized(uint8 indexed ilkIndex, address indexed ilkAddress);
    event IlkSpotUpdated(address newSpot);
    event Initialized(uint64 version);
    event InterestRateModuleUpdated(address newModule);
    event MintAndBurnGem(uint8 indexed ilkIndex, address indexed usr, int256 wad);
    event MintToTreasury(address indexed treasury, uint256 amount, uint256 supplyFactor);
    event Paused(uint8 indexed pauseIndex, address account);
    event RemoveOperator(address indexed from, address indexed to);
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
    event Unpaused(uint8 indexed pauseIndex, address account);
    event WhitelistUpdated(address newWhitelist);
    event Withdraw(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor, uint256 newDebt);
    event WithdrawCollateral(uint8 indexed ilkIndex, address indexed user, address indexed recipient, uint256 amount);
}
