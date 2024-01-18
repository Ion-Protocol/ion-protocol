// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { EthXReserveOracle } from "../../../src/oracles/reserve/EthXReserveOracle.sol";
import { ReserveFeed } from "../../../src/oracles/reserve/ReserveFeed.sol";
import { IStaderStakePoolsManager } from "../../../src/interfaces/ProviderInterfaces.sol";
import { WadRayMath, RAY } from "../../../src/libraries/math/WadRayMath.sol";
import { ReserveOracle } from "../../../src/oracles/reserve/ReserveOracle.sol";
import { ReserveOracleSharedSetup } from "../../helpers/ReserveOracleSharedSetup.sol";

contract EthXReserveOracleForkTest is ReserveOracleSharedSetup {
    using WadRayMath for *;

    // --- ETHx Reserve Oracle Test ---

    function test_RevertWhen_UpdateIsOnCooldown() public {
        uint256 maxChange = 3e25; // 0.03 3%
        address[] memory feeds = new address[](3);
        uint8 quorum = 0;
        EthXReserveOracle ethXReserveOracle = new EthXReserveOracle(
            STADER_STAKE_POOLS_MANAGER,
            ETHX_ILK_INDEX,
            feeds,
            quorum,
            maxChange
        );

        ethXReserveOracle.updateExchangeRate();

        vm.expectRevert(abi.encodeWithSelector(ReserveOracle.UpdateCooldown.selector, block.timestamp));
        ethXReserveOracle.updateExchangeRate();
    }

    function test_EthXReserveOracleGetProtocolExchangeRate() public {
        uint256 maxChange = 3e25; // 0.03 3%
        address[] memory feeds = new address[](3);
        uint8 quorum = 0;
        EthXReserveOracle ethXReserveOracle = new EthXReserveOracle(
            STADER_STAKE_POOLS_MANAGER,
            ETHX_ILK_INDEX,
            feeds,
            quorum,
            maxChange
        );

        uint256 protocolExchangeRate = ethXReserveOracle.getProtocolExchangeRate();
        assertEq(protocolExchangeRate, 1_010_109_979_339_787_990, "protocol exchange rate");
    }

    function test_EthXReserveOracleAggregation() public {
        uint256 maxChange = 1e27; // 1 100%
        uint8 quorum = 3;

        ReserveFeed reserveFeed1 = new ReserveFeed(address(this));
        ReserveFeed reserveFeed2 = new ReserveFeed(address(this));
        ReserveFeed reserveFeed3 = new ReserveFeed(address(this));

        uint256 reserveFeed1ExchangeRate = 0.9 ether;
        uint256 reserveFeed2ExchangeRate = 0.95 ether;
        uint256 reserveFeed3ExchangeRate = 1 ether;

        reserveFeed1.setExchangeRate(ETHX_ILK_INDEX, reserveFeed1ExchangeRate);
        reserveFeed2.setExchangeRate(ETHX_ILK_INDEX, reserveFeed2ExchangeRate);
        reserveFeed3.setExchangeRate(ETHX_ILK_INDEX, reserveFeed3ExchangeRate);

        address[] memory feeds = new address[](3);
        feeds[0] = address(reserveFeed1);
        feeds[1] = address(reserveFeed2);
        feeds[2] = address(reserveFeed3);
        EthXReserveOracle ethXReserveOracle = new EthXReserveOracle(
            STADER_STAKE_POOLS_MANAGER,
            ETHX_ILK_INDEX,
            feeds,
            quorum,
            maxChange
        );

        uint256 expectedExchangeRate =
            (reserveFeed1ExchangeRate + reserveFeed2ExchangeRate + reserveFeed3ExchangeRate) / 3;
        uint256 protocolExchangeRate = ethXReserveOracle.currentExchangeRate();

        assertEq(protocolExchangeRate, expectedExchangeRate, "min exchange rate");
    }

    // verifying that the change in the swETH storage slot is reflected in exchangeRate()
    function test_EthXReserveOracleForkExchcangeRateChange() public {
        uint256 newTotalSupplyToStore = 2 ether;
        uint256 newTotalEthBalanceToStore = 1 ether;
        uint256 expectedExchangeRate = 0.5 ether;
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_SUPPLY_SLOT, bytes32(newTotalSupplyToStore));
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_ETH_BALANCE_SLOT, bytes32(newTotalEthBalanceToStore));

        uint256 newExchangeRate = IStaderStakePoolsManager(STADER_STAKE_POOLS_MANAGER).getExchangeRate();
        assertEq(newExchangeRate, expectedExchangeRate, "new exchange rate");
    }

    // --- Bounding Scenario ---

    function test_EthXReserveOracleOutputsMin() public {
        uint256 maxChange = 3e25; // 0.03 3%

        uint256 newTotalSupplyToStore = 1 ether;
        uint256 newTotalEthBalanceToStore = 0.5 ether;

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets currentExchangeRate to be the current exchangeRate in constructor
        EthXReserveOracle ethXReserveOracle =
            new EthXReserveOracle(STADER_STAKE_POOLS_MANAGER, ETHX_ILK_INDEX, feeds, quorum, maxChange);

        uint256 exchangeRate = ethXReserveOracle.currentExchangeRate();

        // set EthX exchange rate to be lower
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_SUPPLY_SLOT, bytes32(newTotalSupplyToStore));
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_ETH_BALANCE_SLOT, bytes32(newTotalEthBalanceToStore));
        ethXReserveOracle.updateExchangeRate();

        uint256 newExchangeRate = ethXReserveOracle.currentExchangeRate();

        // should output the min
        uint256 minExchangeRate = exchangeRate - ((exchangeRate * maxChange) / RAY);
        assertEq(newExchangeRate, minExchangeRate, "exchange rate bounded to the minimum");
    }

    function test_EthXReserveOracleOutputsMax() public {
        uint256 maxChange = 25e25; // 0.25 25%

        uint256 newTotalSupplyToStore = 1 ether;
        uint256 newTotalEthBalanceToStore = 3 ether;

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets currentExchangeRate to be the current exchangeRate in constructor
        EthXReserveOracle ethXReserveOracle =
        new EthXReserveOracle(STADER_STAKE_POOLS_MANAGER, ETHX_ILK_INDEX, feeds, quorum,
    maxChange);

        uint256 exchangeRate = ethXReserveOracle.currentExchangeRate();

        // set Swell exchange rate to be lower
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_SUPPLY_SLOT, bytes32(newTotalSupplyToStore));
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_ETH_BALANCE_SLOT, bytes32(newTotalEthBalanceToStore));
        ethXReserveOracle.updateExchangeRate();

        uint256 newExchangeRate = ethXReserveOracle.currentExchangeRate();

        // should output the max
        uint256 maxExchangeRate = exchangeRate + ((exchangeRate * maxChange) / RAY);
        assertEq(newExchangeRate, maxExchangeRate, "exchange rate bounded to the maximum");
    }

    function test_EthXReserveOracleOutputsUnbounded() public {
        uint256 maxChange = 1e27; // 1 100%

        uint256 newTotalSupplyToStore = 1 ether;
        uint256 newTotalEthBalanceToStore = 1 ether;
        uint256 expectedExchangeRate = newTotalEthBalanceToStore.wadDivDown(newTotalSupplyToStore);

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets currentExchangeRate to be the current exchangeRate in constructor
        EthXReserveOracle ethXReserveOracle =
        new EthXReserveOracle(STADER_STAKE_POOLS_MANAGER, ETHX_ILK_INDEX, feeds, quorum,
    maxChange);

        // set Swell exchange rate to new but within bounds
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_SUPPLY_SLOT, bytes32(newTotalSupplyToStore));
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_ETH_BALANCE_SLOT, bytes32(newTotalEthBalanceToStore));
        ethXReserveOracle.updateExchangeRate();

        uint256 newExchangeRate = ethXReserveOracle.currentExchangeRate();

        // should output the newly calculated exchange rate
        assertEq(newExchangeRate, expectedExchangeRate, "exchange rate is unbounded");
    }
}
