// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { WstEthReserveOracle } from "src/oracles/reserve/WstEthReserveOracle.sol";
import { WstEthSpotOracle } from "src/oracles/spot/WstEthSpotOracle.sol";
import { EthXReserveOracle } from "src/oracles/reserve/EthXReserveOracle.sol";
import { EthXSpotOracle } from "src/oracles/spot/EthXSpotOracle.sol";
import { SwEthReserveOracle } from "src/oracles/reserve/SwEthReserveOracle.sol";
import { SwEthSpotOracle } from "src/oracles/spot/SwEthSpotOracle.sol";

import { BaseScript } from "script/Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

// TODO: Move to constants
address constant WST_ETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant STADER_STAKE_POOLS_MANAGER = 0xcf5EA1b38380f6aF39068375516Daf40Ed70D299;
address constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;

address constant MAINNET_ETH_PER_STETH_CHAINLINK = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
address constant MAINNET_SWETH_ETH_UNISWAP_01 = 0x30eA22C879628514f1494d4BBFEF79D21A6B49A2; // 0.05% fee
address constant MAINNET_USD_PER_ETHX_REDSTONE = 0xFaBEb1474C2Ab34838081BFdDcE4132f640E7D2d;
address constant MAINNET_WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
address constant MAINNET_USD_PER_ETH_CHAINLINK = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

uint8 constant STETH_ILK_INDEX = 0;
uint8 constant ETHX_ILK_INDEX = 1;
uint8 constant SWETH_ILK_INDEX = 2;

uint256 constant MAX_CHANGE = 0.03e27; // 0.03 3%

// TODO: Move to config
uint256 constant WST_ETH_LTV = 0.92e27;
uint256 constant ETHX_LTV = 0.95e27;
uint256 constant SWETH_LTV = 0.9e27;

// TODO: Alter this after observations are increased
uint32 constant SWETH_SECONDS_AGO = 1;

contract DeployInitialReserveAndSpotOraclesScript is BaseScript {
    using StdJson for string;

    function run()
        public
        broadcast
        returns (
            WstEthReserveOracle wstEthReserveOracle,
            EthXReserveOracle ethXReserveOracle,
            SwEthReserveOracle swEthReserveOracle,
            WstEthSpotOracle wstEthSpotOracle,
            EthXSpotOracle ethXSpotOracle,
            SwEthSpotOracle swEthSpotOracle
        )
    {
        wstEthReserveOracle = new WstEthReserveOracle(WST_ETH, STETH_ILK_INDEX, new address[](3), 0, MAX_CHANGE);
        ethXReserveOracle =
            new EthXReserveOracle(STADER_STAKE_POOLS_MANAGER, ETHX_ILK_INDEX, new address[](3), 0, MAX_CHANGE);
        swEthReserveOracle = new SwEthReserveOracle(SWETH, SWETH_ILK_INDEX, new address[](3), 0, MAX_CHANGE);

        wstEthSpotOracle =
        new WstEthSpotOracle(WST_ETH_LTV, address(wstEthReserveOracle), MAINNET_ETH_PER_STETH_CHAINLINK, MAINNET_WSTETH);
        ethXSpotOracle =
        new EthXSpotOracle(ETHX_LTV, address(ethXReserveOracle), MAINNET_USD_PER_ETHX_REDSTONE, MAINNET_USD_PER_ETH_CHAINLINK);
        swEthSpotOracle =
            new SwEthSpotOracle(SWETH_LTV, address(swEthReserveOracle), MAINNET_SWETH_ETH_UNISWAP_01, SWETH_SECONDS_AGO);
    }
}
