// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";
import { SwEthSpotOracle } from "src/oracles/spot/SwEthSpotOracle.sol";
import { WstEthSpotOracle } from "src/oracles/spot/WstEthSpotOracle.sol";
import { EthXSpotOracle } from "src/oracles/spot/EthXSpotOracle.sol";

import { ReserveOracle } from "src/oracles/reserve/ReserveOracle.sol";
import { SwEthReserveOracle } from "src/oracles/reserve/SwEthReserveOracle.sol";
import { WstEthReserveOracle } from "src/oracles/reserve/WstEthReserveOracle.sol";
import { EthXReserveOracle } from "src/oracles/reserve/EthxReserveOracle.sol";

import { IStaderOracle } from "src/interfaces/ProviderInterfaces.sol";

import { ReserveOracleSharedSetup } from "test/helpers/ReserveOracleSharedSetup.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";

import { console2 } from "forge-std/console2.sol";

// fork tests for integrating with external contracts
contract SpotOracleForkTest is ReserveOracleSharedSetup {
    using WadRayMath for uint256;

    // spot oracle constructor configs
    address constant MAINNET_ETH_PER_STETH_CHAINLINK = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    address constant MAINNET_SWETH_ETH_UNISWAP_01 = 0x30eA22C879628514f1494d4BBFEF79D21A6B49A2; // 0.05% fee
    address constant MAINNET_SWETH_ETH_UNISWAP_02 = 0x4Ac5056DE171ee09E7AfA069DD1a3538D2381565; // 0.3%
    address constant MAINNET_USD_PER_ETHX_REDSTONE = 0xFaBEb1474C2Ab34838081BFdDcE4132f640E7D2d;
    address constant MAINNET_WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant MAINNET_USD_PER_ETH_CHAINLINK = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    uint8 constant SWETH_FEED_DECIMALS = 18;
    uint8 constant STETH_FEED_DECIMALS = 18;
    uint8 constant ETHX_FEED_DECIMALS = 18;

    SpotOracle stEthSpotOracle;
    SpotOracle swEthSpotOracle;
    SpotOracle ethXSpotOracle;

    ReserveOracle stEthReserveOracle;
    ReserveOracle swEthReserveOracle;
    ReserveOracle ethXReserveOracle;

    function setUp() public override {
        // fork test
        // mainnetFork = vm.createSelectFork(MAINNET_RPC_URL); // specify blockheight?
        // vm.rollFork(BLOCK_NUMBER);
        super.setUp();

        // instantiate reserve oracles
        address[] memory feeds = new address[](3);
        stEthReserveOracle = new WstEthReserveOracle(
            WSTETH,
            ILK_INDEX,
            feeds,
            QUORUM,
            MAX_CHANGE
        );

        ethXReserveOracle = new EthXReserveOracle(
            STADER_STAKE_POOLS_MANAGER,
            ILK_INDEX,
            feeds,
            QUORUM,
            MAX_CHANGE
        );

        swEthReserveOracle = new SwEthReserveOracle(
            SWETH,
            ILK_INDEX,
            feeds,
            QUORUM,
            MAX_CHANGE
        );
        // update e
    }

    // --- stETH Spot Oracle Test ---

    function test_WstEthSpotOracleViewPrice() public {
        // mainnet values
        // stETH per wstETH = 1143213397000524230
        // ETH per stETH    =  999698915670794300
        // ETH per wstETH   = (ETH per stETH) * (stETH per wstETH) = 1.1428692e18 (1142869193361749358)
        uint256 ltv = 0.5e27; // 0.5

        stEthSpotOracle = new WstEthSpotOracle(
            STETH_ILK_INDEX, 
            ltv,
            address(stEthReserveOracle), 
            MAINNET_ETH_PER_STETH_CHAINLINK, 
            MAINNET_WSTETH
        );

        uint256 price = stEthSpotOracle.getPrice();
        assertEq(price, 1_142_869_193_361_749_358, "ETH per wstETH price");
    }

    function test_WstEthSpotOracleViewSpot() public {
        uint256 ltv = 0.8e27; // 0.8

        stEthSpotOracle = new WstEthSpotOracle(
            STETH_ILK_INDEX, 
            ltv, 
            address(stEthReserveOracle),
            MAINNET_ETH_PER_STETH_CHAINLINK, 
            MAINNET_WSTETH
        );

        uint256 expectedPrice = stEthSpotOracle.getPrice();
        uint256 expectedSpot = ltv.wadMulDown(expectedPrice);

        assertEq(stEthSpotOracle.getSpot(), expectedSpot, "spot");
    }

    function test_WstEthSpotOracleUsesPriceAsMin() public {
        uint256 ltv = 1e27; // 1 100%

        stEthSpotOracle = new WstEthSpotOracle(
            STETH_ILK_INDEX, 
            ltv, 
            address(stEthReserveOracle),
            MAINNET_ETH_PER_STETH_CHAINLINK, 
            MAINNET_WSTETH
        );

        uint256 price = stEthSpotOracle.getPrice();
        console2.log("price in test", price);

        // update reserve oracle price
        // uint256 clBalance = uint256(vm.load(LIDO, LIDO_CL_BALANCE_SLOT));
        // uint256 newClBalance = clBalance + 5000000 ether;
        // uint256 newExchangeRate = changeStEthClBalance(newClBalance);
        // stEthReserveOracle.updateExchangeRate();

        // assertTrue(newExchangeRate > price);

        uint256 expectedSpot = ltv.wadMulDown(price);

        assertEq(stEthSpotOracle.getSpot(), expectedSpot, "spot uses the exchangeRate as the minimum");
    }

    // --- swETH Spot Oracle Test ---
    // uniswap twap oracle

    function test_SwEthSpotOracleViewPrice() public {
        // mainnet values
        // stETH per wstETH = 1143213397000524230
        // ETH per stETH    =  999698915670794300
        // ETH per wstETH   = (ETH per stETH) * (stETH per wstETH) = 1.1428692e18 (1142869193361749358)
        uint256 ltv = 0.5e27;

        swEthSpotOracle = new SwEthSpotOracle(
            SWETH_ILK_INDEX, 
            ltv, 
            address(swEthReserveOracle), 
            MAINNET_SWETH_ETH_UNISWAP_01,
            100
        );

        uint256 price = swEthSpotOracle.getPrice(); // 1 ETH is 0.992 swETH
        assertEq(price, 1_007_326_342_304_993_374, "ETH per swETH price");
    }

    function test_SwEthSpotOracleViewSpot() public {
        uint256 ltv = 0.95e27;
        uint32 secondsAgo = 100;

        swEthSpotOracle =
        new SwEthSpotOracle(SWETH_ILK_INDEX, ltv, address(swEthReserveOracle), MAINNET_SWETH_ETH_UNISWAP_01, secondsAgo);

        uint256 expectedPrice = swEthSpotOracle.getPrice();
        uint256 expectedSpot = ltv.wadMulDown(expectedPrice);

        assertEq(swEthSpotOracle.getSpot(), expectedSpot, "spot");
    }

    function test_SwEthSpotOracleUsesExchangeRateAsMin() public {
        uint256 ltv = 1e27;
        uint32 secondsAgo = 100;

        swEthSpotOracle =
        new SwEthSpotOracle(SWETH_ILK_INDEX, ltv, address(swEthReserveOracle), MAINNET_SWETH_ETH_UNISWAP_01, secondsAgo);

        // update exchange rate
        uint256 newExchangeRate = 0.9e18;
        changeSwEthExchangeRate(newExchangeRate);
        swEthReserveOracle.updateExchangeRate();

        uint256 expectedPrice = swEthSpotOracle.getPrice();
        uint256 expectedSpot = ltv.wadMulDown(newExchangeRate);

        assertEq(swEthSpotOracle.getSpot(), expectedSpot, "spot");
    }

    // --- ETHx Spot Oracle Test ---

    // redstone oracle
    function test_EthXSpotOracleViewPrice() public {
        uint256 ltv = 0.7e27;
        ethXSpotOracle = new EthXSpotOracle(
            ETHX_ILK_INDEX,
            ltv, 
            address(ethXReserveOracle),
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
        uint256 ltv = 0.85e27;

        ethXSpotOracle = new EthXSpotOracle(
            ETHX_ILK_INDEX,
            ltv, 
            address(ethXReserveOracle), 
            MAINNET_USD_PER_ETHX_REDSTONE, 
            MAINNET_USD_PER_ETH_CHAINLINK
        );

        changeStaderOracleExchangeRate(2e18, 1e18); // 2 ETH per ETHx

        ethXReserveOracle.updateExchangeRate();

        uint256 expectedPrice = ethXSpotOracle.getPrice();
        uint256 expectedSpot = ltv.wadMulDown(expectedPrice);

        assertEq(ethXSpotOracle.getSpot(), expectedSpot, "spot");
    }

    // --- Minimum between reserve oracle and spot price ---
    function test_EthXSpotOracleUsesExchangeRateAsMin() public {
        uint256 ltv = 1e27;

        ethXSpotOracle = new EthXSpotOracle(
            ETHX_ILK_INDEX,
            ltv, 
            address(ethXReserveOracle), 
            MAINNET_USD_PER_ETHX_REDSTONE, 
            MAINNET_USD_PER_ETH_CHAINLINK
        );

        uint256 newExchangeRate = 0.5e18;
        changeStaderOracleExchangeRate(newExchangeRate, 1e18); // 0.5 ETH per ETHx

        ethXReserveOracle.updateExchangeRate();

        uint256 expectedPrice = ethXSpotOracle.getPrice();
        uint256 expectedSpot = ltv.wadMulDown(newExchangeRate);

        assertEq(ethXSpotOracle.getSpot(), expectedSpot, "spot");
    }
}
