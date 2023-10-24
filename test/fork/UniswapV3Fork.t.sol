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
    // if true, then we care about stETH. if false, then we care about swETH
    bool swETH_stETH_flag = true;
    bool writeToFile = true;
    
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
        // console2.log("SQRT PRICE", sqrtPriceX96O);
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

    function simForkTest(int256 amountSpecified, uint160 sqrtPriceLimitX96, address poolAddress) 
        internal returns (uint256, uint256, uint256) {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        uniswapPool = IUniswapPoolV3(poolAddress);
        bool zeroForOne = swETH_stETH_flag;
        bytes memory data;

        uint256 necessaryBalance = uint256(amountSpecified);
        vm.deal(address(this), necessaryBalance);
        weth.deposit{ value: necessaryBalance }();
        weth.approve(address(uniswapPool), type(uint256).max);

        // BEFORE
        uint256 oldRawPrice = getPrice();
        uint256 native;
        if (swETH_stETH_flag) {
            native = swETH.balanceOf(address(this));
        } else {
            native = stETH.balanceOf(address(this));
        }
        // console2.log("BFORE PRICE", oldRawPrice);
        // SWAP
        uniswapPool.swap(address(this), zeroForOne, amountSpecified, sqrtPriceLimitX96, data);
        // AFTER
        uint256 newRawPrice = getPrice();
        // console2.log("AFTER PRICE", newRawPrice);
        // RESULTS
        // console2.log("DIFF PRICE", newRawPrice - oldRawPrice);
        uint256 percDiff = ((newRawPrice - oldRawPrice) * 1e18) / oldRawPrice;
        // console2.log("PERC DIFF", percDiff * 100);
        if (swETH_stETH_flag) {
            native = swETH.balanceOf(address(this));
        } else {
            native = stETH.balanceOf(address(this));
        }
        console2.log(necessaryBalance, oldRawPrice, (percDiff * 100), native);
        return (oldRawPrice, newRawPrice, native);
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
        // configure range here
        int256 increment = 5e18;
        int256 starting = 1900e18; // inclusive
        int256 ending = 2101e18; // exclusive

        swETH_stETH_flag = true; 
        uint160 sqrtPriceLimitX96 = 0.9999e18; 
        uint256 len = uint256((ending - starting) / increment);
        int256[] memory depositAmounts = new int256[](len);
        for (uint256 i = 0; i < len; i++) {
            depositAmounts[i] = starting + int256(i) * increment;
        }

        string memory path = "./offchain/files/swETH_output.csv";
        string memory header = "amountSpecified,oldPrice,newPrice,swapReceived";
        console2.log(header);
        if (writeToFile) {
            vm.writeLine(path, header);
        }

        for (uint256 i = 0; i < len; i++) {
            int256 amountSpecified = depositAmounts[i];
            console2.log("--------------------------------------------------");
            console2.log("[swETH] AMOUNT SPECIFIED:", amountSpecified);
            (uint256 oldP, uint256 newP, uint256 swapValue) = simForkTest(amountSpecified, sqrtPriceLimitX96, uniswapSwEthAddress);
            if (writeToFile) {
                string memory oldPString = StringUtils.uint256ToString(oldP);
                string memory newPString = StringUtils.uint256ToString(newP);
                string memory swapValueString = StringUtils.uint256ToString(swapValue);
                string memory amountSpecifiedString = StringUtils.uint256ToString(uint256(amountSpecified));
                string memory row = string(abi.encodePacked(amountSpecifiedString, ",", oldPString, ",", newPString, ",", swapValueString));
                vm.writeLine(path, row);
            }
        }
    }

    function testSwETHCurrentRate() external {
        uniswapPool = IUniswapPoolV3(uniswapSwEthAddress);
        swETH.approve(address(uniswapPool), type(uint256).max);
        console2.log("[swETH] CURRENT TOTAL RESERVES", swETH.balanceOf(address(uniswapPool)));
    }
}