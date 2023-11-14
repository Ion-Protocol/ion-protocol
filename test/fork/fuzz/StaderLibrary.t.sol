// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { StaderLibrary } from "src/libraries/StaderLibrary.sol";
import { IStaderStakePoolsManager, IStaderConfig } from "src/interfaces/ProviderInterfaces.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";

contract StaderLibrary_FuzzTest is Test {
    using StaderLibrary for IStaderStakePoolsManager;

    IStaderStakePoolsManager private constant MAINNET_STADER_DEPOSIT =
        IStaderStakePoolsManager(0xcf5EA1b38380f6aF39068375516Daf40Ed70D299);
    address constant MAINNET_ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function testForkFuzz_GetEthAmountInForLstAmountOut(uint256 lstAmount) external {
        vm.assume(lstAmount != 0);
        vm.assume(lstAmount < type(uint96).max);

        IStaderConfig config = MAINNET_STADER_DEPOSIT.staderConfig();
        uint256 minDepositAmount = config.getMinDepositAmount();
        uint256 maxDepositAmount = config.getMaxDepositAmount();

        uint256 ethAmountIn = MAINNET_STADER_DEPOSIT.getEthAmountInForLstAmountOut(lstAmount);

        vm.assume(ethAmountIn >= minDepositAmount);
        vm.assume(ethAmountIn <= maxDepositAmount);

        MAINNET_STADER_DEPOSIT.deposit{ value: ethAmountIn }(address(this));

        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(this)), lstAmount);
    }

    function testForkFuzz_GetLstAmountOutForEthAmountIn(uint256 ethAmount) external {
        vm.assume(ethAmount != 0);
        vm.assume(ethAmount < type(uint96).max);

        IStaderConfig config = MAINNET_STADER_DEPOSIT.staderConfig();
        uint256 minDepositAmount = config.getMinDepositAmount();
        uint256 maxDepositAmount = config.getMaxDepositAmount();

        vm.assume(ethAmount >= minDepositAmount);
        vm.assume(ethAmount <= maxDepositAmount);

        uint256 lstAmountOut = MAINNET_STADER_DEPOSIT.getLstAmountOutForEthAmountIn(ethAmount);

        MAINNET_STADER_DEPOSIT.deposit{ value: ethAmount }(address(this));

        assertEq(IERC20(address(MAINNET_ETHX)).balanceOf(address(this)), lstAmountOut);
    }
}
