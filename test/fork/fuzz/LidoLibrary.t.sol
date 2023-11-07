// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { LidoLibrary } from "src/libraries/LidoLibrary.sol";
import { IWstEth } from "src/interfaces/ProviderInterfaces.sol";
import { IStEth } from "src/interfaces/ProviderInterfaces.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

contract LidoLibrary_FuzzTest is Test {
    using LidoLibrary for IWstEth;

    IWstEth private constant MAINNET_WSTETH = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    // Checks that ethAmountIn given by function
    function testForkFuzz_getEthAmountInForLstAmountOut(uint256 lstAmount) external {
        vm.assume(lstAmount != 0);
        vm.assume(lstAmount < type(uint128).max);

        uint256 ethAmountIn = LidoLibrary.getEthAmountInForLstAmountOut(MAINNET_WSTETH, lstAmount);

        IStEth stEth = IStEth(MAINNET_WSTETH.stETH());
        vm.assume(ethAmountIn < stEth.getCurrentStakeLimit());

        vm.deal(address(this), ethAmountIn);
        MAINNET_WSTETH.depositForLst(ethAmountIn);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(this)), lstAmount);
    }

    function testForkFuzz_getLstAmountOutForEthAmountIn(uint256 ethAmount) external {
        vm.assume(ethAmount != 0);
        vm.assume(ethAmount < type(uint128).max);

        IStEth stEth = IStEth(MAINNET_WSTETH.stETH());
        vm.assume(ethAmount < stEth.getCurrentStakeLimit());
        uint256 lstAmountOut = LidoLibrary.getLstAmountOutForEthAmountIn(MAINNET_WSTETH, ethAmount);

        vm.deal(address(this), ethAmount);
        MAINNET_WSTETH.depositForLst(ethAmount);
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(this)), lstAmountOut);
    }
}
