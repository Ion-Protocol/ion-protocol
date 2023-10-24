// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { SwellLibrary } from "src/libraries/SwellLibrary.sol";
import { ISwellDeposit } from "src/interfaces/DepositInterfaces.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

contract SwellLibrary_FuzzTest is Test {
    ISwellDeposit private constant MAINNET_SWELL = ISwellDeposit(0xf951E335afb289353dc249e82926178EaC7DEd78);

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    // Checks that ethAmountIn given by function
    function testForkFuzz_getEthAmountInForLstAmountOut(uint256 lstAmount) external {
        vm.assume(lstAmount != 0);
        vm.assume(lstAmount < type(uint96).max);

        uint256 ethAmountIn = SwellLibrary.getEthAmountInForLstAmountOut(MAINNET_SWELL, lstAmount);

        MAINNET_SWELL.deposit{ value: ethAmountIn }();

        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(this)), lstAmount);
    }

    function testForkFuzz_getLstAmountOutForEthAmountIn(uint256 ethAmount) external {
        vm.assume(ethAmount != 0);
        vm.assume(ethAmount < type(uint96).max);

        uint256 lstAmountOut = SwellLibrary.getLstAmountOutForEthAmountIn(MAINNET_SWELL, ethAmount);

        MAINNET_SWELL.deposit{ value: ethAmount }();
        assertEq(IERC20(address(MAINNET_SWELL)).balanceOf(address(this)), lstAmountOut);
    }
}
