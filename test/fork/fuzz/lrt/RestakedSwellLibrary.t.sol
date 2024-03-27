// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { RestakedSwellLibrary } from "../../../../src/libraries/lrt/RestakedSwellLibrary.sol";
import { IRswEth } from "../../../../src/interfaces/ProviderInterfaces.sol";
import { RSWETH } from "../../../../src/Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";

contract RestakedSwellLibraryTest is Test {
    using RestakedSwellLibrary for IRswEth;

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function testForkFuzz_GetEthAmountInForLstAmountOut(uint128 lstAmount) external {
        vm.assume(lstAmount != 0);

        uint256 ethAmountIn = RSWETH.getEthAmountInForLstAmountOut(lstAmount);

        vm.deal(address(this), ethAmountIn);
        RSWETH.depositForLrt(ethAmountIn);

        assertEq((RSWETH).balanceOf(address(this)), lstAmount);
    }

    function testForkFuzz_GetLstAmountOutForEthAmountIn(uint256 ethAmount) external {
        vm.assume(ethAmount != 0);
        vm.assume(ethAmount < type(uint128).max);

        uint256 lstAmountOut = RSWETH.getLstAmountOutForEthAmountIn(ethAmount);

        vm.deal(address(this), ethAmount);
        RSWETH.depositForLrt(ethAmount);
        assertEq((RSWETH).balanceOf(address(this)), lstAmountOut);
    }
}
