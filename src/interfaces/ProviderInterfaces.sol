// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IStEth {
    function submit(address _referral) external payable returns (uint256);

    function getTotalPooledEther() external view returns (uint256);

    function getTotalShares() external view returns (uint256);

    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);

    function getCurrentStakeLimit() external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);
}

interface IWstEth {
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
/// @notice This struct holds data related to the exchange rate between ETH and ETHX.
struct ExchangeRate {
    /// @notice The block number when the exchange rate was last updated.
    uint256 reportingBlockNumber;
    /// @notice The total balance of Ether (ETH) in the system.
    uint256 totalETHBalance;
    /// @notice The total supply of the liquid staking token (ETHX) in the system.
    uint256 totalETHXSupply;
}

interface IStaderOracle {
    function getExchangeRate() external view returns (ExchangeRate memory);
}

interface ISwEth {
    function deposit() external payable;

    function swETHToETHRate() external view returns (uint256);

    function ethToSwETHRate() external view returns (uint256);

    function getRate() external view returns (uint256);
}
