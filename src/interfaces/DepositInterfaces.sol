// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface ILidoStEthDeposit {
    function submit(address _referral) external payable returns (uint256);

    function getTotalPooledEther() external view returns (uint256);

    function getTotalShares() external view returns (uint256);

    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);

    function getCurrentStakeLimit() external view returns (uint256);
}

interface ILidoWStEthDeposit {
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
}

interface IStaderDeposit {
    function deposit(address _receiver) external payable;

    function previewDeposit(uint256 _assets) external view returns (uint256);

    function getExchangeRate() external view returns (uint256);
}

interface ISwellDeposit {
    function deposit() external payable;

    function swETHToETHRate() external view returns (uint256);

    function ethToSwETHRate() external view returns (uint256);
}
