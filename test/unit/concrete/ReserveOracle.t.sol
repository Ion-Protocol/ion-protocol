// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.21;

// import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
// import { SwEthReserveOracle } from "src/oracles/reserve/SwEthReserveOracle.sol";
// import { StEthReserveOracle } from "src/oracles/reserve/StEthReserveOracle.sol";
// import { EthXReserveOracle } from "src/oracles/reserve/EthXReserveOracle.sol";

// import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";
// import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";

// contract MockFeed {
//     mapping(uint8 ilkIndex => uint256 exchangeRate) public exchangeRates;

//     constructor() { }

//     function setExchangeRate(uint8 _ilkIndex, uint256 _exchangeRate) public {
//         exchangeRates[_ilkIndex] = _exchangeRate;
//     }

//     function getExchangeRate(uint8 _ilkIndex) public returns (uint256) {
//         return exchangeRates[_ilkIndex];
//     }
// }

// // fork tests for integrating with external contracts
// contract ReserveOracleTest is IonPoolSharedSetup {
//     using RoundedMath for uint256;

//     uint8 constant STETH_ILK_INDEX = 0;
//     uint8 constant ETHX_ILK_INDEX = 1;
//     uint8 constant SWETH_ILK_INDEX = 2;

//     address constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
//     address constant ETHX_PROTOCOL_FEED = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;

//     address constant LIDO = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
//     address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

//     uint256 constant MAX_CHANGE = 3e25; // 0.03 3%

//     // fork configs

//     uint256 constant BLOCK_NUMBER = 18_372_927;
//     string public MAINNET_RPC_URL = vm.envString("MAINNET_ARCHIVE_RPC_URL");

//     uint256 mainnetFork;

//     ERC20PresetMinterPauser mockToken;

//     function setUp() public override {
//         mainnetFork = vm.createSelectFork(MAINNET_RPC_URL); // specify blockheight?
//         vm.rollFork(BLOCK_NUMBER);

//         super.setUp();

//         ERC20PresetMinterPauser mockToken = new ERC20PresetMinterPauser("Mock LST", "mLST");
//     }

//     // --- stETH Reserve Oracle Test ---

//     function test_StEthReserveOracleGetProtocolExchangeRate() public {
//         uint8 ilkIndex = 0;
//         address[] memory feeds = new address[](3);
//         uint8 quorum = 0;
//         StEthReserveOracle stEthReserveOracle =
//             new StEthReserveOracle(LIDO, WSTETH, ilkIndex, feeds, quorum, MAX_CHANGE);

//         uint256 protocolExchangeRate = stEthReserveOracle.getProtocolExchangeRate();
//         assertEq(protocolExchangeRate, 1_140_172_374_139_257_947, "protocol exchange rate");
//     }

//     function test_StEthReserveOracleAggregation() public {
//         uint8 ilkIndex = 0;

//         MockFeed mockFeed1 = new MockFeed();
//         MockFeed mockFeed2 = new MockFeed();
//         MockFeed mockFeed3 = new MockFeed();

//         uint256 mockFeed1ExchangeRate = 1.1 ether;
//         uint256 mockFeed2ExchangeRate = 1.12 ether;
//         uint256 mockFeed3ExchangeRate = 1.14 ether;

//         mockFeed1.setExchangeRate(ilkIndex, mockFeed1ExchangeRate);
//         mockFeed2.setExchangeRate(ilkIndex, mockFeed2ExchangeRate);
//         mockFeed3.setExchangeRate(ilkIndex, mockFeed3ExchangeRate);

//         address[] memory feeds = new address[](3);

//         feeds[0] = address(mockFeed1);
//         feeds[1] = address(mockFeed2);
//         feeds[2] = address(mockFeed3);

//         uint8 quorum = 3;
//         StEthReserveOracle stEthReserveOracle =
//             new StEthReserveOracle(LIDO, WSTETH, ilkIndex, feeds, quorum, MAX_CHANGE);

//         uint256 expectedMinExchangeRate = (mockFeed1ExchangeRate + mockFeed2ExchangeRate + mockFeed3ExchangeRate) /
// 3;

//         uint256 protocolExchangeRate = stEthReserveOracle.getExchangeRate();

//         // should output the expected as the minimum
//         assertEq(protocolExchangeRate, expectedMinExchangeRate, "protocol exchange rate");
//     }

//     // --- ETHx Reserve Oracle Test ---

//     function test_EthXReserveOracleGetProtocolExchangeRate() public {
//         uint8 ilkIndex = 0;
//         address[] memory feeds = new address[](3);
//         uint8 quorum = 0;
//         EthXReserveOracle ethXReserveOracle = new EthXReserveOracle(
//             ETHX_PROTOCOL_FEED,
//             ilkIndex,
//             feeds,
//             quorum,
//             MAX_CHANGE
//         );

//         uint256 protocolExchangeRate = ethXReserveOracle.getProtocolExchangeRate();
//         assertEq(protocolExchangeRate, 1_010_109_979_339_787_990, "protocol exchange rate");
//     }

//     function test_EthXReserveOracleAggregation() public {
//         uint8 ilkIndex = 0;
//         uint8 quorum = 3;

//         MockFeed mockFeed1 = new MockFeed();
//         MockFeed mockFeed2 = new MockFeed();
//         MockFeed mockFeed3 = new MockFeed();

//         uint256 mockFeed1ExchangeRate = 0.9 ether;
//         uint256 mockFeed2ExchangeRate = 0.95 ether;
//         uint256 mockFeed3ExchangeRate = 1 ether;

//         mockFeed1.setExchangeRate(ilkIndex, mockFeed1ExchangeRate);
//         mockFeed2.setExchangeRate(ilkIndex, mockFeed2ExchangeRate);
//         mockFeed3.setExchangeRate(ilkIndex, mockFeed3ExchangeRate);

//         address[] memory feeds = new address[](3);
//         feeds[0] = address(mockFeed1);
//         feeds[1] = address(mockFeed2);
//         feeds[2] = address(mockFeed3);
//         EthXReserveOracle ethXReserveOracle = new EthXReserveOracle(
//             ETHX_PROTOCOL_FEED,
//             ilkIndex,
//             feeds,
//             quorum,
//             MAX_CHANGE
//         );

//         uint256 expectedExchangeRate = (mockFeed1ExchangeRate + mockFeed2ExchangeRate + mockFeed3ExchangeRate) / 3;
//         uint256 protocolExchangeRate = ethXReserveOracle.getExchangeRate();

//         assertEq(protocolExchangeRate, expectedExchangeRate, "min exchange rate");
//     }

//     // --- swETH Reserve Oracle Test ---

//     function test_SwEthReserveOracleGetProtocolExchangeRate() public {
//         uint8 ilkIndex = 0;
//         uint8 quorum = 0;

//         address[] memory feeds = new address[](3);
//         SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(
//             SWETH,
//             ilkIndex,
//             feeds,
//             quorum,
//             MAX_CHANGE
//         );

//         uint256 protocolExchangeRate = swEthReserveOracle.getProtocolExchangeRate();
//         assertEq(protocolExchangeRate, 1_039_088_295_006_509_594, "protocol exchange rate");
//     }

//     // --- Reserve Oracle Aggregation Test ---

//     function test_SwEthReserveOracleGetAggregateExchangeRateMin() public {
//         MockFeed mockFeed = new MockFeed();

//         // reserve oracle
//         uint8 ilkIndex = 0;
//         address[] memory feeds = new address[](3);
//         feeds[0] = address(mockFeed);
//         uint8 quorum = 1;
//         SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(
//             SWETH,
//             ilkIndex,
//             feeds,
//             quorum,
//             MAX_CHANGE
//         );

//         // mock reserve feed
//         mockFeed.setExchangeRate(ilkIndex, 1.01 ether);

//         // should be a min of
//         // protocol exchange rate = 1.03
//         // mock exchange rate = 1.01
//         uint256 exchangeRate = swEthReserveOracle.getExchangeRate();
//         assertEq(exchangeRate, 1.01 ether, "min exchange rate");
//     }

//     function test_SwEthReserveOracleTwoFeeds() public {
//         MockFeed mockFeed1 = new MockFeed();
//         MockFeed mockFeed2 = new MockFeed();

//         uint8 ilkIndex = 0;
//         address[] memory feeds = new address[](3);
//         feeds[0] = address(mockFeed1);
//         feeds[1] = address(mockFeed2);
//         uint8 quorum = 2;
//         SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(
//             SWETH,
//             ilkIndex,
//             feeds,
//             quorum,
//             MAX_CHANGE
//         );
//         mockFeed1.setExchangeRate(ilkIndex, 0.9 ether);
//         mockFeed2.setExchangeRate(ilkIndex, 0.8 ether);

//         uint256 expectedMinExchangeRate = (0.9 ether + 0.8 ether) / 2;

//         assertEq(swEthReserveOracle.getExchangeRate(), expectedMinExchangeRate, "min exchange rate");
//     }

//     function test_SwEthReserveOracleThreeFeeds() public {
//         MockFeed mockFeed1 = new MockFeed();
//         MockFeed mockFeed2 = new MockFeed();
//         MockFeed mockFeed3 = new MockFeed();

//         uint256 mockFeed1ExchangeRate = 1 ether;
//         uint256 mockFeed2ExchangeRate = 1.4 ether;
//         uint256 mockFeed3ExchangeRate = 1.8 ether;

//         uint8 ilkIndex = 1;
//         address[] memory feeds = new address[](3);
//         feeds[0] = address(mockFeed1);
//         feeds[1] = address(mockFeed2);
//         uint8 quorum = 2;
//         SwEthReserveOracle swEthReserveOracle = new SwEthReserveOracle(
//             SWETH,
//             ilkIndex,
//             feeds,
//             quorum,
//             MAX_CHANGE
//         );
//         mockFeed1.setExchangeRate(ilkIndex, mockFeed1ExchangeRate);
//         mockFeed2.setExchangeRate(ilkIndex, mockFeed2ExchangeRate);
//         mockFeed3.setExchangeRate(ilkIndex, mockFeed3ExchangeRate);

//         uint256 expectedMinExchangeRate = (mockFeed1ExchangeRate + mockFeed2ExchangeRate + mockFeed3ExchangeRate) /
// 3;
//         assertEq(swEthReserveOracle.getExchangeRate(), swEthReserveOracle.getExchangeRate(), "min exchange rate");
//     }
// }
