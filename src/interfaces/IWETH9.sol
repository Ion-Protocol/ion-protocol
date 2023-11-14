// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev WETH9 interface
 */
interface IWETH9 is IERC20 {
    /**
     * @dev Deposit ether to get wrapped ether
     */
    function deposit() external payable;

    /**
     * @dev Withdraw wrapped ether to get ether
     * @param amount Amount of wrapped ether to withdraw
     */
    function withdraw(uint256 amount) external;
}
