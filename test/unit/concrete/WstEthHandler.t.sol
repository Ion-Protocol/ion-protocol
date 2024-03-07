// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WstEthHandler } from "../../../src/flash/lst/WstEthHandler.sol";
import { Whitelist } from "../../../src/Whitelist.sol";

import { IonPoolSharedSetup } from "../../helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "../../helpers/ERC20PresetMinterPauser.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract MockUniswapPool {
    address underlying;

    function token0() external pure returns (address) {
        return address(0);
    }

    function token1() external view returns (address) {
        return underlying;
    }

    function setUnderlying(address _underlying) external {
        underlying = _underlying;
    }

    function fee() external pure returns (uint24) {
        return 500;
    }
}

contract WstEthHandler_Test is IonPoolSharedSetup {
    WstEthHandler wstEthHandler;

    uint8 ilkIndex = 0;

    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function setUp() public override {
        super.setUp();

        MockUniswapPool mockPool = new MockUniswapPool();
        mockPool.setUnderlying(address(underlying));

        // Ignore Uniswap args since they will be tested through forks

        // Deploy preset ERC20 code to STETH constant address to be compatible with constructor
        vm.etch(STETH, address(wstEth).code);

        wstEthHandler = new WstEthHandler(
            ilkIndex, ionPool, gemJoins[ilkIndex], Whitelist(whitelist), IUniswapV3Pool(address(mockPool))
        );

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        ERC20PresetMinterPauser(_getUnderlying()).mint(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender1);
        underlying.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, 1e18, new bytes32[](0));
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

        wstEthHandler.depositAndBorrow(depositAmount, borrowAmount, new bytes32[](0));

        assertEq(underlying.balanceOf(address(this)), borrowAmount);
        assertEq(wstEth.balanceOf(address(this)), 0);
    }

    function test_RepayAndWithdraw() external {
        uint256 depositAmount = 1e18; // in wstEth
        uint256 borrowAmount = 0.5e18; // in weth

        wstEth.mint(address(this), depositAmount);
        wstEth.approve(address(wstEthHandler), depositAmount);
        ionPool.addOperator(address(wstEthHandler));

        wstEthHandler.depositAndBorrow(depositAmount, borrowAmount, new bytes32[](0));

        underlying.approve(address(wstEthHandler), borrowAmount);

        assertEq(underlying.balanceOf(address(this)), borrowAmount);
        assertEq(wstEth.balanceOf(address(this)), 0);

        wstEthHandler.repayAndWithdraw(borrowAmount, depositAmount);

        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(wstEth.balanceOf(address(this)), depositAmount);
    }

    function _getDebtCeiling(uint8) internal pure override returns (uint256) {
        return type(uint256).max;
    }
}
