// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { KelpDaoLibrary } from "../../../src/libraries/KelpDaoLibrary.sol";
import { IRsEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { RSETH, RSETH_LRT_DEPOSIT_POOL, ETH_ADDRESS, RSETH_LRT_CONFIG } from "../../../src/Constants.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

import { Test } from "forge-std/Test.sol";

contract KelpDaoLibrary_FuzzTest is Test {
    using KelpDaoLibrary for IRsEth;

    uint256 currentAssetLimit;
    uint256 min;

    function setUp() external {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        currentAssetLimit = RSETH_LRT_DEPOSIT_POOL.getAssetCurrentLimit(ETH_ADDRESS);
        min = RSETH_LRT_DEPOSIT_POOL.minAmountToDeposit();
    }

    function testForkFuzz_GetEthAmountInForLstAmountOut(uint128 lrtAmount) external {
        uint256 ethAmountIn = RSETH.getEthAmountInForLstAmountOut(lrtAmount);

        vm.assume(ethAmountIn < currentAssetLimit);

        uint256 totalMax = currentAssetLimit - ethAmountIn;

        vm.assume(ethAmountIn >= min);
        vm.assume(ethAmountIn <= totalMax);

        vm.deal(address(this), ethAmountIn);
        RSETH.depositForLrt(ethAmountIn);
        assertEq(RSETH.balanceOf(address(this)), lrtAmount);
    }

    function testForkFuzz_GetLstAmountOutForEthAmountIn(uint256 ethAmountIn) external {
        vm.assume(ethAmountIn < currentAssetLimit);

        uint256 totalMax = currentAssetLimit - ethAmountIn;

        vm.assume(ethAmountIn >= min);
        vm.assume(ethAmountIn <= totalMax);

        uint256 lrtAmountOut = RSETH.getLstAmountOutForEthAmountIn(ethAmountIn);

        vm.deal(address(this), ethAmountIn);
        RSETH.depositForLrt(ethAmountIn);
        assertEq(RSETH.balanceOf(address(this)), lrtAmountOut);
    }
}
