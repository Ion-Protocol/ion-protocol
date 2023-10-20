// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.21;

// import { ERC20PresetMinterPauser } from "../helpers/ERC20PresetMinterPauser.sol";
// import { RoundedMath } from "src/math/RoundedMath.sol";

// import "src/oracles/reserve-oracles/ReserveOracle.sol";
// import "test/helpers/IonPoolSharedSetup.sol";


// contract MockFeed {
//     uint256 exchangeRate; 

//     constructor(uint256 _exchangeRate) {
//         exchangeRate = _exchangeRate; 
//     }

//     function getExchangeRate() public returns (uint256) {
//         return exchangeRate; 
//     }
// }

// contract MockReserveOracle is ReserveOracle {

//     address public protocolFeed; 

//     constructor(address _token, uint8 _ilkCount, address _protocolFeed) ReserveOracle(_token, _ilkCount) {
//         protocolFeed = _protocolFeed;    
//         // initialize initial exchange rate
//         exchangeRate = _getProtocolExchangeRate(); 
//         // initialize delayed exchange rate 
//         nextExchangeRate = exchangeRate; 
//     }
// }

// // fork tests for integrating with external contracts
// contract ReserveOracleTest is IonPoolSharedSetup {
//     using RoundedMath for uint256;

//     uint8 constant STETH_ILK_INDEX = 0;
//     uint8 constant ETHX_ILK_INDEX = 1;
//     uint8 constant SWETH_ILK_INDEX = 2;

//     // fork configs

//     uint256 constant BLOCK_NUMBER = 18_372_927;
//     string public MAINNET_RPC_URL = vm.envString("MAINNET_ARCHIVE_RPC_URL");

//     uint256 mainnetFork;

//     ERC20PresetMinterPauser mockToken; 

//     function setUp() public override {
//         super.setUp();

//         ERC20PresetMinterPauser mockToken = new ERC20PresetMinterPauser("Mock LST", "mLST");
//     }

//     // --- Generalized Mock Test --- 

//     function test_ReserveOracleWithMockFeed() public {
//         MockFeed mockFeed = new MockFeed(1.1 ether); 
//         MockReserveOracle mockReserveOracle = new MockReserveOracle(address(mockToken), 1, address(mockFeed));

//     }

//     function test_ReserveOracleAggregationWithMockFeeds() public {
        
//     }

//     function test_ReserveOracleAggregationBelowQuorum() public {

//     }

//     function test_ReserveOracleAggregationAboveQuorum() public {

//     }

//     // --- Fork Tests ---
//     // mainnetFork = vm.createSelectFork(MAINNET_RPC_URL); // specify blockheight?
//     // vm.rollFork(BLOCK_NUMBER);

//     // --- stETH Reserve Oracle Test ---

//     // --- ETHx Reserve Oracle Test --- 

//     // --- swETH Reserve Oracle Test --- 
// }
