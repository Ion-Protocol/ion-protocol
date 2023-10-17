// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import "src/oracles/spot-oracles/SpotOracle.sol";
import "src/oracles/spot-oracles/SwEthSpotOracle.sol"; 
import "src/oracles/spot-oracles/StEthSpotOracle.sol"; 
import "src/oracles/spot-oracles/EthXSpotOracle.sol"; 
import "test/helpers/IonPoolSharedSetup.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
// import "forge-std/console.sol"; 

contract GasHelpers {
    string private checkpointLabel;
    uint256 private checkpointGasLeft = 1; // Start the slot warm.

    function startMeasuringGas() internal virtual {
        // checkpointLabel = label;

        checkpointGasLeft = gasleft();
    }

    function stopMeasuringGas() internal virtual {
        uint256 checkpointGasLeft2 = gasleft();

        // Subtract 100 to account for the warm SLOAD in startMeasuringGas.
        uint256 gasDelta = checkpointGasLeft - checkpointGasLeft2 - 100;
        console.log("gasDelta: ", gasDelta); 
        // emit log_named_uint(string(abi.encodePacked(checkpointLabel, " Gas")), gasDelta);
    }
}

// fork tests for integrating with external contracts
contract SpotOracleTest is IonPoolSharedSetup, GasHelpers {

    // constructor configs 
    address constant MAINNET_ETH_PER_STETH_CHAINLINK = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant MAINNET_SWETH_ETH_UNISWAP_01 = 0x30eA22C879628514f1494d4BBFEF79D21A6B49A2; // 0.05% fee
    address constant MAINNET_SWETH_ETH_UNISWAP_02 = 0x4Ac5056DE171ee09E7AfA069DD1a3538D2381565; // 0.3% 
    address constant MAINNET_USD_PER_ETHX_REDSTONE = 0xFaBEb1474C2Ab34838081BFdDcE4132f640E7D2d; 
    address constant MAINNET_WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; 
    address constant MAINNET_USD_PER_ETH_CHAINLINK = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419; 

    uint8 constant SWETH_FEED_DECIMALS = 18;
    uint8 constant STETH_FEED_DECIMALS = 18;
    uint8 constant ETHX_FEED_DECIMALS = 18;

    uint8 constant STETH_ILK_INDEX = 0; 
    uint8 constant ETHX_ILK_INDEX = 1; 
    uint8 constant SWETH_ILK_INDEX = 2; 

    // fork configs 

    uint256 constant BLOCK_NUMBER = 18372927;

    string public MAINNET_RPC_URL = vm.envString("MAINNET_ARCHIVE_RPC_URL"); 

    uint256 mainnetFork; 

    SpotOracle swEthSpotOracle; 
    SpotOracle stEthSpotOracle; 
    SpotOracle ethXSpotOracle; 

    UniswapTwapViewer uniswapTwapViewer; 

    function setUp() public override {
        super.setUp();

        // fork test
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL); // specify blockheight? 
        vm.rollFork(BLOCK_NUMBER); 
        assertEq(vm.activeFork(), mainnetFork); 
        assertEq(block.number, BLOCK_NUMBER); 

        // deploy contracts

        stEthSpotOracle = new StEthSpotOracle(STETH_FEED_DECIMALS, STETH_ILK_INDEX, address(ionPool), MAINNET_ETH_PER_STETH_CHAINLINK, MAINNET_WSTETH);
        ethXSpotOracle = new EthXSpotOracle(ETHX_FEED_DECIMALS, ETHX_ILK_INDEX, address(ionPool), MAINNET_USD_PER_ETHX_REDSTONE, MAINNET_USD_PER_ETH_CHAINLINK);
    
        uniswapTwapViewer = new UniswapTwapViewer(MAINNET_SWETH_ETH_UNISWAP_01); 
    
    }

    // --- stETH Spot Oracle Test ---

    function test_StEthSpotOracleViewPrice() public {

        // mainnet values 
        // stETH per wstETH = 1143213397000524230 
        // ETH per stETH    =  999698915670794300
        // ETH per wstETH   = (ETH per stETH) * (stETH per wstETH) = 1.1428692e18 (1142869193361749358)

        uint256 price = stEthSpotOracle.getPrice(); 
        assertEq(price, 1142869193361749358, "ETH per wstETH price"); 
    }   

    function test_StEthSpotPushToIonPool() public {

    }

    // --- swETH Spot Oracle Test --- 
    // uniswap twap oracle

    function test_ViewUniswap() public {

        uniswapTwapViewer = new UniswapTwapViewer(MAINNET_SWETH_ETH_UNISWAP_01); 
        // uniswapTwapViewer = new UniswapTwapViewer(0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168); 
        
        // changing intervals between times, but querying 10 different points in time
        // for (uint i = 1; i < 10; i++) {
        //     uniswapTwapViewer.twap(0, i, 10); 
        // }

        // 
        for (uint i = 0; i < 100; i++) { // diff start time 
            for (uint j = 1; j < 10; j++) { // diff intervals
                uniswapTwapViewer.twap(i, j, 10); // 10 intervals from each start time
            }
        }


        // at a constant interval, the diff between each secondsAgo is the same 
        // accumulator values: 10 20 30 40 50 
        // ^ this means the price never changed? 
        // but don't they not record it if price didn't change? 
        // no matter the interval, the twap output will be the same 

        // increase cardinality? 
        // uniswapTwapViewer.increaseCardinality(10);
        // uniswapTwapViewer.twap(3, 10);
    }

    function test_OracleLibraryMultipleContracts() public {
        uniswapTwapViewer = new UniswapTwapViewer(MAINNET_SWETH_ETH_UNISWAP_01);
        for (uint32 i = 1; i < 10; i++) {
            uniswapTwapViewer.consult(i);  
        }

        // usdc 
        uniswapTwapViewer = new UniswapTwapViewer(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
        for (uint32 i = 1; i < 10; i++) {
            uniswapTwapViewer.consult(i);  
        }

        // btc 
        uniswapTwapViewer = new UniswapTwapViewer(0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0);
        for (uint32 i = 1; i < 10; i++) {
            uniswapTwapViewer.consult(i);  
        }

        // 
        uniswapTwapViewer = new UniswapTwapViewer(0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52);
        for (uint32 i = 1; i < 10; i++) {
            uniswapTwapViewer.consult(i);  
        }
    }

    function test_OracleLibraryPerBlock() public {
        vm.rollFork(BLOCK_NUMBER); 

        // uniswapTwapViewer = new UniswapTwapViewer(MAINNET_SWETH_ETH_UNISWAP_01);
        // uint32 secondsAgo = 10; 
        // uint256 skip = 100; 
        // uint256 count = 1; 
        // console.log("starting block: ", block.number); 
        // for (uint256 i = block.number; i >= block.number - (skip * count); i = i - skip) {
        //     vm.rollFork(i); 
        //     console.log("block number: ", block.number); 
        //     uniswapTwapViewer.consult(secondsAgo); 
        // }
    }

    function test_UniswapCardinalityCost() public {
        vm.rollFork(BLOCK_NUMBER); 
        // uniswapTwapViewer = new UniswapTwapViewer(0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52);
        IUniswapV3Pool pool = IUniswapV3Pool(MAINNET_SWETH_ETH_UNISWAP_01); 
        // pool.increaseCardinality(10); // 7591 
        // pool.increaseCardinality(100); // 7591
        startMeasuringGas(); 
        pool.increaseObservationCardinalityNext(139); // 7591
        stopMeasuringGas(); 

    }

    function test_stEthSpotOracleZeroInterval() public {
        // should return current price 
    }

    function test_SwEthSpotOracleViewPrice() public {
        uint32 twapInterval = 5; 
        swEthSpotOracle = new SwEthSpotOracle(SWETH_FEED_DECIMALS, SWETH_ILK_INDEX, address(ionPool), MAINNET_SWETH_ETH_UNISWAP_01, twapInterval);
        uint256 price = swEthSpotOracle.getPrice();
        // 992726942603100178
        // assertEq(price, 1, "ETH per swETH price");  

        twapInterval = 10; 
        swEthSpotOracle = new SwEthSpotOracle(SWETH_FEED_DECIMALS, SWETH_ILK_INDEX, address(ionPool), MAINNET_SWETH_ETH_UNISWAP_01, twapInterval);
        price = swEthSpotOracle.getPrice();
        // assertEq(price, 1, "ETH per swETH price");  

        twapInterval = 20; 
        swEthSpotOracle = new SwEthSpotOracle(SWETH_FEED_DECIMALS, SWETH_ILK_INDEX, address(ionPool), MAINNET_SWETH_ETH_UNISWAP_01, twapInterval);
        price = swEthSpotOracle.getPrice();
        // assertEq(price, 1, "ETH per swETH price");  
        

    }
    
    function test_SwEthSpotPushToIonPool() public {
    }

    // --- ETHx Spot Oracle Test --- 

    // redstone oracle 
    function test_EthXSpotOracleViewPrice() public {
        uint256 price = ethXSpotOracle.getPrice();       
        
        // mainnet values 
        // USD per ETHx 1580.07804587 
        // USD per ETH 1562.37303912
        // ETH per ETHx = (USD per ETHx) / (USD per ETH) = 1.011332125111408905 ETH / ETHx 

        assertEq(price, 1011332125111408905, "ETH per ETHx price"); 
    }

    function test_EthXSpotPushToIonPool() public {
        
    }


}