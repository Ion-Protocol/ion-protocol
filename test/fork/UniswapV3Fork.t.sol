// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { IWETH9 } from "../../src/interfaces/IWETH9.sol";
import { console2 } from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IUniswapPoolV3 {
    function slot0() external returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256, int256);
    function ticks(int24) external returns (
        uint128 liquidityGross, 
        int128 liquidityNet, 
        uint256 feeGrowthOutside0X128,
        uint256 feeGrowthOutside1X128,
        int56 tickCumulativeOutside,
        uint160 secondsPerLiquidityOutsideX128,
        uint32 secondsOutside,
        bool initialized
    );

}

library StringUtils {
    function uint256ToString(uint256 _value) internal pure returns (string memory) {
        if (_value == 0) {
            return "0";
        }
        uint256 temp = _value;
        uint256 digits;
        while (temp > 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_value > 0) {
            buffer[--digits] = bytes1(uint8(48 + _value % 10));
            _value /= 10;
        }
        return string(buffer);
    }
}

contract UniswapSwapTester is Test {
    address constant uniswapStEthAddress = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;
    address constant uniswapSwEthAddress = 0x30eA22C879628514f1494d4BBFEF79D21A6B49A2;
    address constant erc20StEthAddress = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // wstETH
    address constant erc20SwEthAddress = 0xf951E335afb289353dc249e82926178EaC7DEd78; // swETH
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant swETH = IERC20(erc20SwEthAddress);
    IERC20 constant stETH = IERC20(erc20StEthAddress);

    IUniswapPoolV3 uniswapPool;
    // if true, then we care about swETH. if false, then we care about stETH
    bool swETH_stETH_flag = true;
    bool writeToFile = true;
    string path;
    
    // UNISWAP CALLBACK/HELPER FUNCTIONS
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        int256 toSend;
        if (swETH_stETH_flag) {
            toSend = amount0Delta;  
        } else {
            toSend = amount1Delta;
        }
        // console2.log("AMOUNT SENDING", toSend);
        weth.transfer(address(uniswapPool), uint256(toSend));
    }

    function getPrice() internal returns (uint256){
        (uint160 sqrtPriceX96O,,,,,,) = uniswapPool.slot0();
        uint256 num;
        uint256 div;
        if (swETH_stETH_flag) {
            num = 2**96;
            div = sqrtPriceX96O;
        } else {
            num = sqrtPriceX96O;
            div = 2**96;
        }
        return (num * 1e18) / div;
    }

    function getPriceAndTick() internal returns (uint256, int24){
        (uint160 sqrtPriceX96O,int24 tick,,,,,) = uniswapPool.slot0();
        uint256 num;
        uint256 div;
        if (swETH_stETH_flag) {
            num = 2**96;
            div = sqrtPriceX96O;
        } else {
            num = sqrtPriceX96O;
            div = 2**96;
        }
        return ((num * 1e18) / div, tick);
    }

    function simForkTest(int256 amountSpecified, uint160 sqrtPriceLimitX96, address poolAddress) 
        internal {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        uniswapPool = IUniswapPoolV3(poolAddress);
        // bool zeroForOne = swETH_stETH_flag;
        bytes memory data;

        uint256 necessaryBalance = uint256(amountSpecified);
        vm.deal(address(this), necessaryBalance);
        weth.deposit{ value: necessaryBalance }();
        weth.approve(address(uniswapPool), type(uint256).max);

        // BEFORE
        (uint256 oldRawPrice) = getPrice();
        uint256 native;
        if (swETH_stETH_flag) {
            native = swETH.balanceOf(address(this));
        } else {
            native = stETH.balanceOf(address(this));
        }

        // SWAP
        uniswapPool.swap(address(this), swETH_stETH_flag, amountSpecified, sqrtPriceLimitX96, data);
        // AFTER
        (uint256 newRawPrice) = getPrice();


        // RESULTS
        uint256 totalSwETHinPool = swETH.balanceOf(address(uniswapPool));
        uint256 totalEthinPool = weth.balanceOf(address(uniswapPool));
        console2.log("POOL BALANCE", totalSwETHinPool, totalEthinPool);
        // uint256 percDiff = ((newRawPrice - oldRawPrice) * 1e18) / oldRawPrice;
        if (swETH_stETH_flag) {
            native = swETH.balanceOf(address(this));
        } else {
            native = stETH.balanceOf(address(this));
        }
        // perc diff is in 2 decimal places now 
        console2.log(necessaryBalance, newRawPrice, (((newRawPrice - oldRawPrice) * 1e18) / oldRawPrice / 1e14), native);
        if (writeToFile) {
            string memory oldPString = StringUtils.uint256ToString(oldRawPrice);
            string memory newPString = StringUtils.uint256ToString(newRawPrice);
            string memory swapValueString = StringUtils.uint256ToString(native);
            string memory amountSpecifiedString = StringUtils.uint256ToString(necessaryBalance);
            string memory ethInPoolString = StringUtils.uint256ToString(totalEthinPool);
            string memory swETHInPoolString = StringUtils.uint256ToString(totalSwETHinPool);
            string memory row = string(abi.encodePacked(
                amountSpecifiedString, ",", 
                oldPString, ",", 
                newPString, ",", 
                swapValueString, ",",
                ethInPoolString, ",",
                swETHInPoolString
            ));
            vm.writeLine(path, row);
        }
    }


    // SET UP
    function setUp() external {
        // set up mainnet fork
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        swETH.approve(address(this), type(uint256).max);
        stETH.approve(address(this), type(uint256).max);
    }


    // TESTS
    function testSwETHSwap() external {
        swETH_stETH_flag = true;
        int256 amountSpecified = 2037e18; // Amount of ETH to swap
        simForkTest(amountSpecified, 0.9999e18, uniswapSwEthAddress);
    }

    // 2092 - 16%
    // 2093 - 87%
    // 2099 - garbage
    function testSwETHSwapLimit() external {
        swETH_stETH_flag = true;
        int256 amountSpecified = 2094e18; // Amount of ETH to swap
        simForkTest(amountSpecified, 0.9999e18, uniswapSwEthAddress);
    }

    function testStETHSwap() external {
        swETH_stETH_flag = false;
        uint160 sqrtPriceLimitX96 = 94716228691469861788700436331; // target price that you want to pool to be at after the swap?
        int256 amountSpecified = 2900e18; // Amount of ETH to swap
        simForkTest(amountSpecified, sqrtPriceLimitX96, uniswapStEthAddress);
    }
    
    function testSwETHSwapRange() external { 
        uniswapPool = IUniswapPoolV3(uniswapSwEthAddress);
        swETH.approve(address(uniswapPool), type(uint256).max);
        uint256 totalSwETHinPool = swETH.balanceOf(address(uniswapPool));
        uint256 totalEthinPool = weth.balanceOf(address(uniswapPool));
        uint256 currentPrice = getPrice();
        uint256 ethDenomSwEthValue = totalSwETHinPool * currentPrice / 1e18;

        // configure range here
        int256 increment = 5e18;
        int256 starting = int256(ethDenomSwEthValue);
        int256 ending = starting + (increment * 20);
        if (starting < 0) {
            starting = 0;
        }

        swETH_stETH_flag = true; 
        uint160 sqrtPriceLimitX96 = 0.9999e18; 
        uint256 len = uint256((ending - starting) / increment);
        int256[] memory depositAmounts = new int256[](len);
        for (uint256 i = 0; i < len; i++) {
            depositAmounts[i] = starting + int256(i) * increment;
        }

        path = vm.envString("UNISWAP_SWETH_FILE_PATH");
        // write the swETH and ETH balances to our output file
        if (writeToFile) {
            string memory swEthString = StringUtils.uint256ToString(totalSwETHinPool);
            string memory ethString = StringUtils.uint256ToString(totalEthinPool);
            string memory balanceRow = string(abi.encodePacked(swEthString, ",", ethString));
            vm.writeLine(path, balanceRow);
        }

        string memory header = "amountSpecified,oldPrice,newPrice,swapReceived,ethInPool,swEthInPool";
        if (writeToFile) {
            vm.writeLine(path, header);
        }

        for (uint256 i = 0; i < len; i++) {
            int256 amountSpecified = depositAmounts[i];
            console2.log("--------------------------------------------------");
            console2.log("[swETH] AMOUNT SPECIFIED:", amountSpecified);
            simForkTest(
                amountSpecified, 
                sqrtPriceLimitX96, 
                uniswapSwEthAddress
            );
        }
    }

    function testSwETHCurrentRate() external {
        uniswapPool = IUniswapPoolV3(uniswapSwEthAddress);
        swETH.approve(address(uniswapPool), type(uint256).max);
        console2.log("[swETH] CURRENT TOTAL RESERVES", swETH.balanceOf(address(uniswapPool)));
    }

    function testReadTicks() external {
        uniswapPool = IUniswapPoolV3(uniswapSwEthAddress);
        swETH_stETH_flag = true;    
        for (int24 i = 0; i < 1000; i += 10) {
            (uint128 liquidity,,,,,,,) = uniswapPool.ticks(i);
            if (liquidity > 0) {
                console2.log(i);
                console2.log(liquidity);
            }
        }
    }
}