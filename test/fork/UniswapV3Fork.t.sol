// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { IWETH9 } from "../../src/interfaces/IWETH9.sol";
import { console2 } from "forge-std/console2.sol";


interface IUniswapPoolV3 {
    function slot0() external returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256, int256);
}

contract UniswapSwapTester is Test {
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IUniswapPoolV3 constant uniswapPool = IUniswapPoolV3(0x30eA22C879628514f1494d4BBFEF79D21A6B49A2);
    uint256 internal constant INITIAL_BALANCE = 1000e18;
    
    function setUp() external {
        // set up mainnet fork
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function testSwap() external {
        // set up params for swap
        bool zeroForOne = true; // Swap ETH to token
        bytes memory data; // Additional data if needed
        uint160 sqrtPriceLimitX96 = 0.9928e18; // target price that you want to pool to be at after the swap?
        int256 amountSpecified = 500e18; // Amount of ETH to swap
        // obtain funds
        vm.deal(address(this), INITIAL_BALANCE);
        // simulate swap (first get WETH, then send to uniswap pool)
        vm.startPrank(address(this));
        // BEFORE
        (uint160 sqrtPriceX96Old,,,,,,) = uniswapPool.slot0();
        uint256 oldRawPrice =  2**96 * 1e18 / sqrtPriceX96Old;
        console2.log("BEFOR", oldRawPrice);
        // SWAP
        weth.deposit{ value: INITIAL_BALANCE }();
        weth.approve(address(uniswapPool), type(uint256).max);
        uniswapPool.swap(address(this), zeroForOne, amountSpecified, sqrtPriceLimitX96, data);
        // AFTER
        (uint160 sqrtPriceX96New,,,,,,) = uniswapPool.slot0();
        uint256 newRawPrice = 2**96 * 1e18 / sqrtPriceX96New;
        console2.log("AFTER", newRawPrice);

        console2.log("DIFF", newRawPrice - oldRawPrice);
        uint256 percDiff = ((newRawPrice - oldRawPrice) * 1e18) / oldRawPrice;
        console2.log("PERC DIFF", percDiff);

        vm.stopPrank();
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external {
        weth.transfer(address(uniswapPool), uint256(amount0Delta));
    }
}