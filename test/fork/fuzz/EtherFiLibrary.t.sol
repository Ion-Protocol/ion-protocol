// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { EtherFiLibrary } from "../../../src/libraries/EtherFiLibrary.sol";
import { IWeEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { WEETH_ADDRESS, EETH_ADDRESS } from "../../../src/Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";

contract EtherFiLibrary_FuzzTest is Test {
    using EtherFiLibrary for IWeEth;

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
    }

    function testForkFuzz_GetEthAmountInForLstAmountOut(uint256 lrtAmount) external {
        vm.assume(lrtAmount > 5);
        vm.assume(lrtAmount < type(uint96).max);

        uint256 ethAmountIn = EtherFiLibrary.getEthAmountInForLstAmountOut(WEETH_ADDRESS, lrtAmount);

        vm.deal(address(this), ethAmountIn);
        WEETH_ADDRESS.depositForLrt(ethAmountIn);
        assertEq(IERC20(address(WEETH_ADDRESS)).balanceOf(address(this)), lrtAmount);
    }

    function testForkFuzz_GetLstAmountOutForEthAmountIn(uint256 ethAmount) external {
        vm.assume(ethAmount != 0);
        vm.assume(ethAmount < type(uint128).max);

        uint256 lrtAmountOut = EtherFiLibrary.getLstAmountOutForEthAmountIn(WEETH_ADDRESS, ethAmount);

        vm.assume(lrtAmountOut != 0);

        vm.deal(address(this), ethAmount);
        WEETH_ADDRESS.depositForLrt(ethAmount);
        assertEq(IERC20(address(WEETH_ADDRESS)).balanceOf(address(this)), lrtAmountOut);
    }
}
