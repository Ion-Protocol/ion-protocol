// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
// import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { TickMath } from "src/oracles/spot-oracles/TickMath.sol"; 
import { UniswapOracleLibrary } from "src/oracles/spot-oracles/UniswapOracleLibrary.sol"; 
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SpotOracle } from "./SpotOracle.sol"; 
import "forge-std/test.sol"; 
import { console2 } from "forge-std/console2.sol"; 
import "@openzeppelin/contracts/utils/Strings.sol"; 

string constant path = "./twap.txt"; 
string constant pricePath = "./twap-price.txt"; 


contract UniswapHelper {
    function _getPriceX96FromSqrtPriceX96(uint256 sqrtPriceX96) public pure returns(uint256 priceX96) {
        return Math.mulDiv(sqrtPriceX96 * sqrtPriceX96, 10**18, 2**192); // [wad]  
    }
}

contract UniswapTwapViewer is Test, UniswapHelper {

    IUniswapV3Pool immutable uniswapPool;

    constructor(address _uniswapPool) {
        uniswapPool = IUniswapV3Pool(_uniswapPool); 
    }

    function increaseCardinality(uint8 newCardinality) public {
        uniswapPool.increaseObservationCardinalityNext(newCardinality); 
    }

    function consult(uint32 secondsAgo) public {
        (int24 arithmeticMeanTick, uint128 harmonicMeanTick) = UniswapOracleLibrary.consult(address(uniswapPool), secondsAgo);
        // console2.log("arithmeticMeanTick: ", arithmeticMeanTick);  
        // console2.log("harmonicMeanTick: ", harmonicMeanTick);  
        
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);
        // console.log("sqrtPriceX96: ", sqrtPriceX96); 
        uint256 price = _getPriceX96FromSqrtPriceX96(sqrtPriceX96);
        console.log("secondsAgo: ", secondsAgo); 
        console.log("price: ", price); 
    }

    function twap(uint256 startTime, uint256 interval, uint256 length) public {
        uint256 time; 

        uint32[] memory secondsAgo = new uint32[](length);
        for (uint8 i; i < length; i++) {
            secondsAgo[i] = uint32(time); 
            time += interval; 
        }  

        (int56[] memory tickCumulatives, ) = uniswapPool.observe(secondsAgo); // returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
        
        
        vm.writeLine(path, " --- interval ---"); 
        vm.writeLine(path, Strings.toString(interval)); 
        
        vm.writeLine(path, " --- seconds ago --- "); 
        for (uint8 i; i < length; i++) {
            console2.log("time: ", secondsAgo[i]);
            console2.log(" tickCumulatives: ", tickCumulatives[i]); 
            string memory sec =  Strings.toString(secondsAgo[i]); 
            vm.writeLine(path, sec); 
            string memory tick = Strings.toString(uint56(tickCumulatives[i]));
            vm.writeLine(path, tick);
        }

        // diffs 
        vm.writeLine(path, " --- diff --- "); 
        for (uint8 i; i < length - 1; i++) {
            console2.log("diff: ", tickCumulatives[i+1] - tickCumulatives[i]);
            string memory diff = Strings.toString(uint56(tickCumulatives[i+1] - tickCumulatives[i])); 
            vm.writeLine(path, diff); 
        }

        // actual price
        vm.writeLine(path, " --- actual price --- "); 
        uint256 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / int56(uint56(interval)))); 
        console2.log("sprtPriceX96: ", sqrtPriceX96); 
        
        uint256 price = uint256(_getPriceX96FromSqrtPriceX96(sqrtPriceX96));
        vm.writeLine(path, Strings.toString(price));

        vm.writeLine(pricePath, "--- prices ---");
        vm.writeLine(pricePath, Strings.toString(startTime)); 
        vm.writeLine(pricePath, Strings.toString(interval));  
        vm.writeLine(pricePath, Strings.toString(price));
        // // diffs 
        // for (uint8 i; i < length - 1; i++) {
        //     console2.log("diff: ", (tickCumulatives[i+1] - tickCumulatives[i]));
        //     vm.writeLine(path, (tickCumulatives[i+1] - tickCumulatives[i])); 
        // }
    }
}


contract SwEthSpotOracle is SpotOracle, UniswapHelper {
    using Math for uint256; 

    IUniswapV3Pool immutable uniswapPool;
    uint32 immutable twapInterval; 

    constructor(uint8 _feedDecimals, uint8 _ilkIndex, address _ionPool, address _uniswapPool, uint32 _twapInterval) SpotOracle(_feedDecimals, _ilkIndex,  _ionPool) {
        uniswapPool = IUniswapV3Pool(_uniswapPool);
        twapInterval = _twapInterval;
    }

    // @dev uses the Uniswap TWAP 
    function _getPrice() internal view override returns (uint256 price) {
    
        uint160 sqrtPriceX96; 
        if (twapInterval == 0) {
            console2.log("twapInterval is zero"); 
            // return the current price if no interval defined 
            (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapPool).slot0();
            console2.log("sqrtPrice: ", sqrtPriceX96); 
        } else {
            console2.log("twapInterval is non zero"); 
            uint32[] memory secondsAgo = new uint32[](5); 
            secondsAgo[0] = 0; 
            secondsAgo[1] = 1;
            secondsAgo[2] = 2;
            secondsAgo[3] = 3;
            secondsAgo[4] = 4;

            // the cumulative difference is regularly 730 
        
            (int56[] memory tickCumulatives, ) = uniswapPool.observe(secondsAgo); // returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
            console2.log("tickCumulatives length: ", tickCumulatives.length); 
            console2.log("tickCumulatives[0]: ", tickCumulatives[0]);
            console2.log("tickCumulatives[1]: ", tickCumulatives[1]); 
            console2.log("tickCumulatives[2]: ", tickCumulatives[2]); 
            console2.log("tickCumulatives[3]: ", tickCumulatives[3]); 
            console2.log("tickCumulatives[4]: ", tickCumulatives[4]); 
            // console2.log("tickCumulatives[5]: ", tickCumulatives[5]); 


            console2.log("tickCumulatives[1] - tickCumulatives[0]: ", tickCumulatives[1] - tickCumulatives[0]);
            console2.log("twapInterval: ", int56(int32(twapInterval))); 
            console2.log("divide: ", (tickCumulatives[1] - tickCumulatives[0]) / int56(int32(twapInterval)));
            
            sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
                int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32((twapInterval))))
            ); 
            console2.log("sprtPriceX96: ", sqrtPriceX96); 
        }

        price = uint256(_getPriceX96FromSqrtPriceX96(sqrtPriceX96));

        // dividing by twapInterval cancels out 
    }   


}
