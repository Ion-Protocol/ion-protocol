// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { RAY } from "../../src/libraries/math/WadRayMath.sol";
import { WeEthWstEthReserveOracle } from "../../src/oracles/reserve/WeEthWstEthReserveOracle.sol";
import { WeEthWstEthSpotOracle } from "../../src/oracles/spot/WeEthWstEthSpotOracle.sol";

// import { WstEthReserveOracle } from "../../src/oracles/reserve/WstEthReserveOracle.sol";
// import { WstEthSpotOracle } from "../../src/oracles/spot/WstEthSpotOracle.sol";
// import { EthXReserveOracle } from "../../src/oracles/reserve/EthXReserveOracle.sol";
// import { EthXSpotOracle } from "../../src/oracles/spot/EthXSpotOracle.sol";
// import { SwEthReserveOracle } from "../../src/oracles/reserve/SwEthReserveOracle.sol";
// import { SwEthSpotOracle } from "../../src/oracles/spot/SwEthSpotOracle.sol";

import { BaseScript } from "../Base.s.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployInitialReserveAndSpotOraclesScript is BaseScript {
    using StdJson for string;

    string configPath = "./deployment-config/05_DeployInitialReserveAndSpotOracles.json";
    string config = vm.readFile(configPath);

    uint256 maxChange = config.readUint(".maxChange");
    uint256 ltv = config.readUint(".ltv");

    function run() public broadcast returns (address reserveOracle, address spotOracle) 
    // WstEthReserveOracle wstEthReserveOracle,
    // EthXReserveOracle ethXReserveOracle,
    // SwEthReserveOracle swEthReserveOracle,
    // WstEthSpotOracle wstEthSpotOracle,
    // EthXSpotOracle ethXSpotOracle,
    // SwEthSpotOracle swEthSpotOracle
    {
        require(maxChange > 0, "maxChange must be greater than 0");
        require(maxChange < RAY, "maxChange must be less than 1");

        require(ltv > 0, "ltv must be greater than 0");
        require(ltv < RAY, "ltv must be less than 1");

        // Specific to using Redstone Oracles
        uint256 maxTimeFromLastUpdate = config.readUint(".maxTimeFromLastUpdate");

        // Needs to change per asset
        reserveOracle = address(new WeEthWstEthReserveOracle(0, new address[](3), 0, maxChange));
        spotOracle = address(new WeEthWstEthSpotOracle(ltv, address(reserveOracle), maxTimeFromLastUpdate));

        // wstEthReserveOracle = new WstEthReserveOracle(WST_ETH, STETH_ILK_INDEX, new address[](3), 0, MAX_CHANGE);
        // ethXReserveOracle =
        //     new EthXReserveOracle(STADER_STAKE_POOLS_MANAGER, ETHX_ILK_INDEX, new address[](3), 0, MAX_CHANGE);
        // swEthReserveOracle = new SwEthReserveOracle(SWETH, SWETH_ILK_INDEX, new address[](3), 0, MAX_CHANGE);

        // wstEthSpotOracle = new WstEthSpotOracle(
        //     WST_ETH_LTV, address(wstEthReserveOracle), MAINNET_ETH_PER_STETH_CHAINLINK, MAINNET_WSTETH
        // );
        // ethXSpotOracle = new EthXSpotOracle(
        //     ETHX_LTV, address(ethXReserveOracle), MAINNET_USD_PER_ETHX_REDSTONE, MAINNET_USD_PER_ETH_CHAINLINK
        // );
        // swEthSpotOracle =
        //     new SwEthSpotOracle(SWETH_LTV, address(swEthReserveOracle), MAINNET_SWETH_ETH_UNISWAP_01,
        // SWETH_SECONDS_AGO);
    }
}
