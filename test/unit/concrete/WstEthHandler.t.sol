// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WstEthHandler } from "src/periphery/handlers/WstEthHandler.sol";

import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract WstEthHandler_Test is IonPoolSharedSetup {
    WstEthHandler wstEthHandler;

    uint8 ilkIndex = 0;

    function setUp() public override {
        super.setUp();

        // Ignore Uniswap args since they will be tested through forks
        wstEthHandler =
        new WstEthHandler(ilkIndex, ionPool, ionRegistry, IUniswapV3Factory(address(1)), IUniswapV3Pool(address(1)), 500);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        uint256 riskAdjustedSpot = 0.9e18;
        ionPool.updateIlkSpot(1, riskAdjustedSpot);

        vm.startPrank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, 1e18);
        vm.stopPrank();
    }

    function test_DepositAndBorrow() external {
        uint256 depositAmount = 1e18; // in wstEth
        uint256 borrowAmount = 0.5e18; // in weth

        wstEth.mint(address(this), depositAmount);
        wstEth.approve(address(wstEthHandler), depositAmount);
        ionPool.addOperator(address(wstEthHandler));

        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(wstEth.balanceOf(address(this)), depositAmount);

        wstEthHandler.depositAndBorrow(depositAmount, borrowAmount);

        assertEq(underlying.balanceOf(address(this)), borrowAmount);
        assertEq(wstEth.balanceOf(address(this)), 0);
    }

    function test_RepayAndWithdraw() external {
        uint256 depositAmount = 1e18; // in wstEth
        uint256 borrowAmount = 0.5e18; // in weth

        wstEth.mint(address(this), depositAmount);
        wstEth.approve(address(wstEthHandler), depositAmount);
        ionPool.addOperator(address(wstEthHandler));

        wstEthHandler.depositAndBorrow(depositAmount, borrowAmount);

        underlying.approve(address(wstEthHandler), borrowAmount);

        assertEq(underlying.balanceOf(address(this)), borrowAmount);
        assertEq(wstEth.balanceOf(address(this)), 0);

        wstEthHandler.repayAndWithdraw(borrowAmount, depositAmount);

        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(wstEth.balanceOf(address(this)), depositAmount);
    }
}
