// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { RenzoLibrary } from "../../../../src/libraries/lrt/RenzoLibrary.sol";
import { EZETH, RENZO_RESTAKE_MANAGER } from "../../../../src/Constants.sol";

import { Test } from "forge-std/Test.sol";

uint256 constant SCALE_FACTOR = 1e18;

contract RenzoLibrary_FuzzTest is Test {
    function setUp() public {
        // vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19387902);
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function test_GetEthAmountInForLstAmountOut() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_472_376);
        uint128 minLrtAmount = 184_626_086_978_191_358;
        testForkFuzz_GetEthAmountInForLstAmountOut(minLrtAmount);
    }

    function test_GetLstAmountOutForEthAmountIn() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_472_376);
        uint128 ethAmount = 185_854_388_659_820_839;
        testForkFuzz_GetLstAmountOutForEthAmountIn(ethAmount);
    }

    function testForkFuzz_GetEthAmountInForLstAmountOut(uint128 minLrtAmount) public {
        (uint256 ethAmount, uint256 actualLrtAmount) = RenzoLibrary.getEthAmountInForLstAmountOut(minLrtAmount);
        assertGe(actualLrtAmount, minLrtAmount, "actualLrtAmount");

        uint256 mintAmount = _calculateMintAmount(ethAmount);

        vm.assume(mintAmount != 0);

        vm.deal(address(this), ethAmount);
        RenzoLibrary.depositForLrt(ethAmount);
        assertEq(EZETH.balanceOf(address(this)), actualLrtAmount, "ezETH balance");
    }

    function testForkFuzz_GetLstAmountOutForEthAmountIn(uint128 ethAmount) public {
        uint256 mintAmount = _calculateMintAmount(ethAmount);

        // Prevent revert
        vm.assume(mintAmount != 0);

        (uint256 lrtAmountOut, uint256 minEthIn) = RenzoLibrary.getLstAmountOutForEthAmountIn(ethAmount);

        assertEq(lrtAmountOut, mintAmount, "ethAmount");

        (lrtAmountOut,) = RenzoLibrary.getLstAmountOutForEthAmountIn(minEthIn);

        assertEq(lrtAmountOut, mintAmount, "minEthIn");

        vm.deal(address(this), ethAmount);
        RenzoLibrary.depositForLrt(ethAmount);
        assertEq(EZETH.balanceOf(address(this)), lrtAmountOut);
    }

    function _calculateMintAmount(uint256 ethAmount) internal view returns (uint256 mintAmount) {
        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();
        uint256 inflationPercentage = SCALE_FACTOR * ethAmount / (totalTVL + ethAmount);
        uint256 newEzETHSupply = (EZETH.totalSupply() * SCALE_FACTOR) / (SCALE_FACTOR - inflationPercentage);
        mintAmount = newEzETHSupply - EZETH.totalSupply();
    }
}
