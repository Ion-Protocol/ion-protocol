// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IXERC20Lockbox {
    error IXERC20Lockbox_Native();
    error IXERC20Lockbox_NotNative();
    error IXERC20Lockbox_WithdrawFailed();

    event Deposit(address _sender, uint256 _amount);
    event Withdraw(address _sender, uint256 _amount);

    receive() external payable;

    function ERC20() external view returns (address);
    function IS_NATIVE() external view returns (bool);
    function XERC20() external view returns (address);
    function deposit(uint256 _amount) external;
    function depositNative() external payable;
    function depositNativeTo(address _to) external payable;
    function depositTo(address _to, uint256 _amount) external;
    function withdraw(uint256 _amount) external;
    function withdrawTo(address _to, uint256 _amount) external;
}
