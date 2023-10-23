// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import "src/oracles/spot-oracles/SpotOracle.sol";
import "src/oracles/spot-oracles/SwEthSpotOracle.sol";
import "src/oracles/spot-oracles/StEthSpotOracle.sol";
import "src/oracles/spot-oracles/EthXSpotOracle.sol";
import "test/helpers/IonPoolSharedSetup.sol";

// fork tests for integrating with external contracts
contract SpotOracleTest is IonPoolSharedSetup {
    using RoundedMath for uint256;

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

    uint256 constant BLOCK_NUMBER = 18_372_927;

    string public MAINNET_RPC_URL = vm.envString("MAINNET_ARCHIVE_RPC_URL");

    uint256 mainnetFork;

    SpotOracle swEthSpotOracle;
    SpotOracle stEthSpotOracle;
    SpotOracle ethXSpotOracle;

    function setUp() public override {
        // fork test
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL); // specify blockheight?
        vm.rollFork(BLOCK_NUMBER);
        super.setUp();
    }

    // --- stETH Spot Oracle Test ---

    function test_StEthSpotOracleViewPrice() public {
        // mainnet values
        // stETH per wstETH = 1143213397000524230
        // ETH per stETH    =  999698915670794300
        // ETH per wstETH   = (ETH per stETH) * (stETH per wstETH) = 1.1428692e18 (1142869193361749358)
        uint64 ltv = 0.5 ether;

        stEthSpotOracle = new StEthSpotOracle(
            STETH_ILK_INDEX, 
            address(ionPool), 
            ltv, 
            MAINNET_ETH_PER_STETH_CHAINLINK, 
            MAINNET_WSTETH
        );

        uint256 price = stEthSpotOracle.getPrice();
        assertEq(price, 1_142_869_193_361_749_358, "ETH per wstETH price");
    }

    function test_StEthSpotOracleViewSpot() public {
        uint64 ltv = 0.8 ether;

        stEthSpotOracle = new StEthSpotOracle(
            STETH_ILK_INDEX, 
            address(ionPool),
            ltv, 
            MAINNET_ETH_PER_STETH_CHAINLINK, 
            MAINNET_WSTETH
        );

        uint256 expectedPrice = stEthSpotOracle.getPrice();
        uint256 expectedSpot = (ltv * expectedPrice).scaleToRay(36);

        assertEq(stEthSpotOracle.getSpot(), expectedSpot, "spot");
    }

    // --- swETH Spot Oracle Test ---
    // uniswap twap oracle

    function test_SwEthSpotOracleViewPrice() public {
        // mainnet values
        // stETH per wstETH = 1143213397000524230
        // ETH per stETH    =  999698915670794300
        // ETH per wstETH   = (ETH per stETH) * (stETH per wstETH) = 1.1428692e18 (1142869193361749358)
        uint64 ltv = 0.5 ether;

        swEthSpotOracle = new SwEthSpotOracle(
            SWETH_ILK_INDEX, 
            address(ionPool), 
            ltv, 
            MAINNET_SWETH_ETH_UNISWAP_01,
            100
        );

        uint256 price = swEthSpotOracle.getPrice(); // 1 ETH is 0.992 swETH
        assertEq(price, 1_007_326_342_304_993_374, "ETH per swETH price");
    }

    function test_SwEthSpotOracleViewSpot() public {
        uint64 ltv = 0.95 ether;
        uint32 secondsAgo = 100;

        SwEthSpotOracle swEthSpotOracle =
            new SwEthSpotOracle(SWETH_ILK_INDEX, address(ionPool), ltv, MAINNET_SWETH_ETH_UNISWAP_01, secondsAgo);

        uint256 expectedPrice = swEthSpotOracle.getPrice();
        uint256 expectedSpot = (ltv * expectedPrice).scaleToRay(36);

        assertEq(swEthSpotOracle.getSpot(), expectedSpot, "spot");
    }

    // // --- ETHx Spot Oracle Test ---

    // redstone oracle
    function test_EthXSpotOracleViewPrice() public {
        uint64 ltv = 0.7 ether;
        ethXSpotOracle = new EthXSpotOracle(
            ETHX_ILK_INDEX,
            address(ionPool),
            ltv, 
            MAINNET_USD_PER_ETHX_REDSTONE,
            MAINNET_USD_PER_ETH_CHAINLINK
        );

        uint256 price = ethXSpotOracle.getPrice();

        // mainnet values
        // USD per ETHx 1580.07804587
        // USD per ETH 1562.37303912
        // ETH per ETHx = (USD per ETHx) / (USD per ETH) = 1.011332125111408905 ETH / ETHx

        assertEq(price, 1_011_332_125_111_408_905, "ETH per ETHx price");
    }

    function test_EthXSpotOracleViewSpot() public {
        uint64 ltv = 0.85 ether;

        EthXSpotOracle ethXSpotOracle = new EthXSpotOracle(
            ETHX_ILK_INDEX,
            address(ionPool), 
            ltv, 
            MAINNET_USD_PER_ETHX_REDSTONE, 
            MAINNET_USD_PER_ETH_CHAINLINK
        );

        uint256 expectedPrice = ethXSpotOracle.getPrice();
        uint256 expectedSpot = (ltv * expectedPrice).scaleToRay(36);

        assertEq(ethXSpotOracle.getSpot(), expectedSpot, "spot");
    }
}
