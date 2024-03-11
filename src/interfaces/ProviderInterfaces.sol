// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IStEth is IERC20 {
    function submit(address _referral) external payable returns (uint256);

    function getTotalPooledEther() external view returns (uint256);

    function getTotalShares() external view returns (uint256);

    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);

    function getCurrentStakeLimit() external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);
}

interface IWstEth is IERC20 {
    function wrap(uint256 _stETHAmount) external returns (uint256);

    /**
     * @notice Exchanges wstETH to stETH
     * @param _wstETHAmount amount of wstETH to uwrap in exchange for stETH
     * @dev Requirements:
     *  - `_wstETHAmount` must be non-zero
     *  - msg.sender must have at least `_wstETHAmount` wstETH.
     * @return Amount of stETH user receives after unwrap
     */
    function unwrap(uint256 _wstETHAmount) external returns (uint256);

    function getStETHByWstETH(uint256 _ETHAmount) external view returns (uint256);

    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);

    function stETH() external view returns (address);

    function stEthPerToken() external view returns (uint256);

    function tokensPerStEth() external view returns (uint256);
}

interface IStaderStakePoolsManager {
    function deposit(address _receiver) external payable returns (uint256);

    function previewDeposit(uint256 _assets) external view returns (uint256);

    function previewWithdraw(uint256 _shares) external view returns (uint256);

    function getExchangeRate() external view returns (uint256);

    function staderConfig() external view returns (IStaderConfig);

    function totalAssets() external view returns (uint256);
}

interface IStaderConfig {
    function getMinDepositAmount() external view returns (uint256);

    function getMaxDepositAmount() external view returns (uint256);

    function getStaderOracle() external view returns (address);
}

/// @title ExchangeRate
/// @notice This struct holds data related to the exchange rate between ETH and ETHx.
struct ExchangeRate {
    /// @notice The block number when the exchange rate was last updated.
    uint256 reportingBlockNumber;
    /// @notice The total balance of Ether (ETH) in the system.
    uint256 totalETHBalance;
    /// @notice The total supply of the liquid staking token (ETHx) in the system.
    uint256 totalETHXSupply;
}

interface IStaderOracle {
    function getExchangeRate() external view returns (ExchangeRate memory);
}

interface IETHx is IERC20 { }

interface ISwEth {
    function deposit() external payable;

    function swETHToETHRate() external view returns (uint256);

    function ethToSwETHRate() external view returns (uint256);

    function getRate() external view returns (uint256);
}

interface IWeEth is IERC20 {
    function getRate() external view returns (uint256);
    function getEETHByWeETH(uint256) external view returns (uint256);

    // Official function technically returns the interface but we won't type it
    // here
    function eETH() external view returns (address);
    function liquidityPool() external view returns (address);
    function wrap(uint256 _eETHAmount) external returns (uint256);
    function unwrap(uint256 _weETHAmount) external returns (uint256);
}

interface IEEth is IERC20 {
    function totalShares() external view returns (uint256);
}

interface IEtherFiLiquidityPool {
    function totalValueOutOfLp() external view returns (uint128);
    function totalValueInLp() external view returns (uint128);
    function amountForShare(uint256 _share) external view returns (uint256);
    function sharesForAmount(uint256 _amount) external view returns (uint256);
    function deposit() external payable returns (uint256);
    function getTotalPooledEther() external view returns (uint256);
    function getTotalEtherClaimOf(address _user) external view returns (uint256);
}

interface IRsEth is IERC20 { }

interface IRswEth is IERC20 {
    function deposit() external payable;
    function ethToRswETHRate() external view returns (uint256);
    function getRate() external view returns (uint256);
    function rswETHToETHRate() external view returns (uint256);
}

interface ILRTOracle {
    function rsETHPrice() external view returns (uint256);
    function updateRSETHPrice() external;
}

interface ILRTDepositPool {
    function getTotalAssetDeposits(address asset) external view returns (uint256);

    function getAssetDistributionData(address asset) external view returns (uint256, uint256, uint256);

    function depositETH(uint256 minRSETHAmountExpected, string calldata referralId) external payable;

    function getRsETHAmountToMint(address asset, uint256 amount) external view returns (uint256);

    function minAmountToDeposit() external view returns (uint256);

    function getAssetCurrentLimit(address asset) external view returns (uint256);
}

interface ILRTConfig {
    function rsETH() external view returns (address);

    function assetStrategy(address asset) external view returns (address);

    function isSupportedAsset(address asset) external view returns (bool);

    function getLSTToken(bytes32 tokenId) external view returns (address);

    function getContract(bytes32 contractId) external view returns (address);

    function getSupportedAssetList() external view returns (address[] memory);

    function depositLimitByAsset(address asset) external view returns (uint256);
}

// Renzo

interface IEzEth is IERC20 { }

interface IRenzoOracle {
    function lookupTokenValue(IERC20 _token, uint256 _balance) external view returns (uint256);
    function lookupTokenAmountFromValue(IERC20 _token, uint256 _value) external view returns (uint256);
    function lookupTokenValues(IERC20[] memory _tokens, uint256[] memory _balances) external view returns (uint256);
    function calculateMintAmount(
        uint256 _currentValueInProtocol,
        uint256 _newValueAdded,
        uint256 _existingEzETHSupply
    )
        external
        pure
        returns (uint256);
    function calculateRedeemAmount(
        uint256 _ezETHBeingBurned,
        uint256 _existingEzETHSupply,
        uint256 _currentValueInProtocol
    )
        external
        pure
        returns (uint256);
}

interface IOperatorDelegator {
    function getTokenBalanceFromStrategy(IERC20 token) external view returns (uint256);

    function deposit(IERC20 _token, uint256 _tokenAmount) external returns (uint256 shares);

    function startWithdrawal(IERC20 _token, uint256 _tokenAmount) external returns (bytes32);

    function getStakedETHBalance() external view returns (uint256);

    function stakeEth(bytes calldata pubkey, bytes calldata signature, bytes32 depositDataRoot) external payable;

    function pendingUnstakedDelayedWithdrawalAmount() external view returns (uint256);
}

interface IRestakeManager {
    function stakeEthInOperatorDelegator(
        IOperatorDelegator operatorDelegator,
        bytes calldata pubkey,
        bytes calldata signature,
        bytes32 depositDataRoot
    )
        external
        payable;
    function depositTokenRewardsFromProtocol(IERC20 _token, uint256 _amount) external;

    function calculateTVLs() external view returns (uint256[][] memory, uint256[] memory, uint256);
    function depositETH(uint256 _referralId) external payable;
}
