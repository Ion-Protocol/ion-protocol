// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SwellLibrary } from "src/libraries/SwellLibrary.sol";
import { ISwellDeposit } from "src/interfaces/DepositInterfaces.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

contract SwellLibrary_FuzzTest is Test {
    using SwellLibrary for ISwellDeposit;

    ISwellDeposit private constant MAINNET_SWELL = ISwellDeposit(0xf951E335afb289353dc249e82926178EaC7DEd78);

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    // Checks that ethAmountIn given by function
    function testForkFuzz_getEthAmountInForLstAmountOut(uint256 lstAmount) external {
        vm.assume(lstAmount != 0);
        vm.assume(lstAmount < type(uint128).max);

        uint256 ethAmountIn = MAINNET_SWELL.getEthAmountInForLstAmountOut(lstAmount);

        vm.deal(address(this), ethAmountIn);
        MAINNET_SWELL.depositForLst(ethAmountIn);

        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(this)), lstAmount);
    }

    function testForkFuzz_getLstAmountOutForEthAmountIn(uint256 ethAmount) external {
        vm.assume(ethAmount != 0);
        vm.assume(ethAmount < type(uint128).max);

        uint256 lstAmountOut = MAINNET_SWELL.getLstAmountOutForEthAmountIn(ethAmount);

        vm.deal(address(this), ethAmount);
        MAINNET_SWELL.depositForLst(ethAmount);
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(this)), lstAmountOut);
    }
}
