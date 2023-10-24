// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SwEthHandler } from "src/periphery/handlers/SwEthHandler.sol";
import { Whitelist } from "src/Whitelist.sol";

import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract SwEthHandler_Test is IonPoolSharedSetup {
    SwEthHandler swEthHandler;

    uint8 ilkIndex = 2;

    function setUp() public override {
        super.setUp();

        // Ignore Uniswap args since they will be tested through forks
        swEthHandler =
        new SwEthHandler(ilkIndex, ionPool, ionRegistry, Whitelist(whitelist), IUniswapV3Factory(address(1)), IUniswapV3Pool(address(1)), 500);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        uint256 riskAdjustedSpot = 0.9e18;
        ionPool.updateIlkSpot(1, riskAdjustedSpot);

        vm.startPrank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, 1e18, new bytes32[](0));
        vm.stopPrank();
    }

    function test_DepositAndBorrow() external {
        uint256 depositAmount = 1e18; // in swEth
        uint256 borrowAmount = 0.5e18; // in weth

        swEth.mint(address(this), depositAmount);
        swEth.approve(address(swEthHandler), depositAmount);
        ionPool.addOperator(address(swEthHandler));

        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(swEth.balanceOf(address(this)), depositAmount);

        swEthHandler.depositAndBorrow(depositAmount, borrowAmount, new bytes32[](0));

        assertEq(underlying.balanceOf(address(this)), borrowAmount);
        assertEq(swEth.balanceOf(address(this)), 0);
    }

    function test_RepayAndWithdraw() external {
        uint256 depositAmount = 1e18; // in swEth
        uint256 borrowAmount = 0.5e18; // in weth

        swEth.mint(address(this), depositAmount);
        swEth.approve(address(swEthHandler), depositAmount);
        ionPool.addOperator(address(swEthHandler));

        swEthHandler.depositAndBorrow(depositAmount, borrowAmount, new bytes32[](0));

        underlying.approve(address(swEthHandler), borrowAmount);

        assertEq(underlying.balanceOf(address(this)), borrowAmount);
        assertEq(swEth.balanceOf(address(this)), 0);

        swEthHandler.repayAndWithdraw(borrowAmount, depositAmount);

        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(swEth.balanceOf(address(this)), depositAmount);
    }
}
