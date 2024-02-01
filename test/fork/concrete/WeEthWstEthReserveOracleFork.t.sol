// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RAY } from "../../../src/libraries/math/WadRayMath.sol";
import { WeEthWstEthReserveOracle } from "../../../src/oracles/reserve/WeEthWstEthReserveOracle.sol";
import { ReserveFeed } from "../../../src/oracles/reserve/ReserveFeed.sol";
import { ReserveOracle } from "../../../src/oracles/reserve/ReserveOracle.sol";
import { IWeEth, IEEth, IEtherFiLiquidityPool } from "../../../src/interfaces/ProviderInterfaces.sol";

import { ReserveOracleSharedSetup } from "../../helpers/ReserveOracleSharedSetup.sol";

import { ETHER_FI_LIQUIDITY_POOL_ADDRESS, WEETH_ADDRESS, EETH_ADDRESS } from "src/Constants.sol";

// fork tests for integrating with external contracts
contract WeEthWstEthReserveOracleForkTest is ReserveOracleSharedSetup {
    function setUp() public override {
        setBlockNumber(19_079_925);
        super.setUp();
    }

    // --- weETH Reserve Oracle Test ---

    function test_RevertWhen_UpdateIsOnCooldown() public {
        uint256 maxChange = 3e25; // 0.03 3%
        address[] memory feeds = new address[](3);
        uint8 quorum = 0;
        WeEthWstEthReserveOracle weEthWstEthReserveOracle =
            new WeEthWstEthReserveOracle(STETH_ILK_INDEX, feeds, quorum, maxChange);

        weEthWstEthReserveOracle.updateExchangeRate();

        vm.expectRevert(abi.encodeWithSelector(ReserveOracle.UpdateCooldown.selector, block.timestamp));
        weEthWstEthReserveOracle.updateExchangeRate();
    }

    function test_WeEthWstEthReserveOracleGetProtocolExchangeRate() public {
        uint256 maxChange = 3e25; // 0.03 3%
        address[] memory feeds = new address[](3);
        uint8 quorum = 0;
        WeEthWstEthReserveOracle weEthWstEthReserveOracle =
            new WeEthWstEthReserveOracle(STETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 protocolExchangeRate = weEthWstEthReserveOracle.getProtocolExchangeRate();
        assertEq(protocolExchangeRate, 891_594_478_806_748_333, "protocol exchange rate");
    }

    // --- Errors ---
    function test_RevertWhen_WeEthWstEthInvalidInitialization() public {
        ReserveFeed reserveFeed1 = new ReserveFeed(address(this));
        ReserveFeed reserveFeed2 = new ReserveFeed(address(this));
        ReserveFeed reserveFeed3 = new ReserveFeed(address(this));

        uint256 maxChange = 3e25; // 0.03 3%
        address[] memory feeds = new address[](3);
        feeds[0] = address(reserveFeed1);
        feeds[1] = address(reserveFeed2);
        feeds[2] = address(reserveFeed3);
        uint8 quorum = 3;

        vm.expectRevert(abi.encodeWithSelector(ReserveOracle.InvalidInitialization.selector, 0));
        new WeEthWstEthReserveOracle(STETH_ILK_INDEX, feeds, quorum, maxChange);
    }

    // --- Slashing Scenario ---

    function test_UnpackEtherFiTotalValue() public {
        uint256 totalValueOutOfLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueOutOfLp();

        uint256 totalValueInLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueInLp();

        // 0x00000000000001287956cfe67f3b5ffe0000000000001e3b21b7e61ce9aac681
        // [totalValueInLp, totalValueOutOfLp]
        bytes32 totalValue = vm.load(address(ETHER_FI_LIQUIDITY_POOL_ADDRESS), EETH_LIQUIDITY_POOL_TOTAL_VALUE_SLOT);

        uint256 unpackedTotalValueInLp = uint256(totalValue >> 128);

        uint256 unpackedTotalValueOutOfLp = uint256(totalValue & EETH_TOTAL_VALUE_MASK);

        assertEq(unpackedTotalValueOutOfLp, totalValueOutOfLp, "totalValueOutOfLp");
        assertEq(unpackedTotalValueInLp, totalValueInLp, "totalValueInLp");
    }

    function test_WeEthExchangeRatePostSlashing() public {
        uint256 totalValueOutOfLpDiff = 10_000 ether;

        uint256 totalValueOutOfLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueOutOfLp();
        uint256 totalValueInLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueInLp();

        bytes32 newTotalValueInLp = bytes32(totalValueInLp) << 128;

        bytes32 newTotalValueOutOfLp = bytes32(uint256(totalValueOutOfLp - totalValueOutOfLpDiff));

        bytes32 newTotalValue = newTotalValueInLp | newTotalValueOutOfLp;

        // reduce rebase share values in EtherFi
        vm.store(address(ETHER_FI_LIQUIDITY_POOL_ADDRESS), EETH_LIQUIDITY_POOL_TOTAL_VALUE_SLOT, bytes32(newTotalValue));

        // _share * getTotalPooledEther() / totalShares
        // _share * (totalValueOutOfLp + totalValueInLp) / totalShares

        uint256 expectedEEthPerWeEthExchangeRate =
            1 ether * (totalValueInLp + uint256(newTotalValueOutOfLp)) / IEEth(EETH_ADDRESS).totalShares();
        uint256 eEthPerWeEthExchangeRate = IWeEth(WEETH_ADDRESS).getEETHByWeETH(1 ether);

        assertEq(eEthPerWeEthExchangeRate, expectedEEthPerWeEthExchangeRate, "new exchange rate");
    }

    // --- Bounding Scenario ---

    // wstETH gets slashed, weETH per stETH goes up
    function test_WstEthExchangeRateGoesDownOutputsMax() public {
        uint256 maxChange = 3e25;
        uint256 newClBalance = 0.5 ether;

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        WeEthWstEthReserveOracle weEthWstEthReserveOracle =
            new WeEthWstEthReserveOracle(STETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 exchangeRate = weEthWstEthReserveOracle.currentExchangeRate();

        vm.store(LIDO, LIDO_CL_BALANCE_SLOT, bytes32(newClBalance));

        weEthWstEthReserveOracle.updateExchangeRate();
        uint256 newExchangeRate = weEthWstEthReserveOracle.currentExchangeRate();

        uint256 maxExchangeRate = exchangeRate + ((exchangeRate * maxChange) / RAY);
        assertEq(newExchangeRate, maxExchangeRate, "max exchange rate bound");
    }

    // weETH gets slashed, weETH per stETH goes down
    function test_WeEthExchangeRateGoesDownOutputsMin() public {
        uint256 maxChange = 5e25;

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets currentExchange rate to be the current exchangeRate in constructor
        WeEthWstEthReserveOracle weEthWstEthReserveOracle =
            new WeEthWstEthReserveOracle(STETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 exchangeRate = weEthWstEthReserveOracle.currentExchangeRate();

        uint256 totalValueInLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueInLp();

        bytes32 newTotalValueInLp = bytes32(totalValueInLp) << 128;

        bytes32 newTotalValueOutOfLp = bytes32(uint256(100 ether));

        bytes32 newTotalValue = newTotalValueInLp | newTotalValueOutOfLp;

        vm.store(address(ETHER_FI_LIQUIDITY_POOL_ADDRESS), EETH_LIQUIDITY_POOL_TOTAL_VALUE_SLOT, bytes32(newTotalValue));

        weEthWstEthReserveOracle.updateExchangeRate();
        uint256 newExchangeRate = weEthWstEthReserveOracle.currentExchangeRate();

        uint256 minExchangeRate = exchangeRate - ((exchangeRate * maxChange) / RAY);
        assertEq(newExchangeRate, minExchangeRate, "minimum exchange rate bound");
    }

    // Exchange Rate Change But Not Bounded

    function test_WstEthExchangeRateGoesDownNotMaxBounded() public {
        uint256 maxChange = 3e25;
        uint256 clBalanceDiff = 1 ether;

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        WeEthWstEthReserveOracle weEthWstEthReserveOracle =
            new WeEthWstEthReserveOracle(STETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 exchangeRate = weEthWstEthReserveOracle.currentExchangeRate();

        bytes32 currClBalance = vm.load(LIDO, LIDO_CL_BALANCE_SLOT);
        uint256 newClBalance = uint256(currClBalance) - clBalanceDiff;

        vm.store(LIDO, LIDO_CL_BALANCE_SLOT, bytes32(newClBalance));

        weEthWstEthReserveOracle.updateExchangeRate();
        uint256 newExchangeRate = weEthWstEthReserveOracle.currentExchangeRate();

        uint256 maxExchangeRate = exchangeRate + ((exchangeRate * maxChange) / RAY);

        assertLt(newExchangeRate, maxExchangeRate, "below max bound");
        assertGt(newExchangeRate, exchangeRate, "above min bound");
    }

    function test_WeEthExchangeRateGoesDownNotMinBounded() public {
        uint256 maxChange = 5e25;
        uint256 totalValueOutOfLpDiff = 1 ether;

        address[] memory feeds = new address[](3);
        uint8 quorum = 0;

        // sets currentExchange rate to be the current exchangeRate in constructor
        WeEthWstEthReserveOracle weEthWstEthReserveOracle =
            new WeEthWstEthReserveOracle(STETH_ILK_INDEX, feeds, quorum, maxChange);

        uint256 exchangeRate = weEthWstEthReserveOracle.currentExchangeRate();

        uint256 totalValueOutOfLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueOutOfLp();

        uint256 totalValueInLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueInLp();

        bytes32 newTotalValueInLp = bytes32(totalValueInLp) << 128;

        bytes32 newTotalValueOutOfLp = bytes32(totalValueOutOfLp - totalValueOutOfLpDiff);

        bytes32 newTotalValue = newTotalValueInLp | newTotalValueOutOfLp;

        vm.store(address(ETHER_FI_LIQUIDITY_POOL_ADDRESS), EETH_LIQUIDITY_POOL_TOTAL_VALUE_SLOT, bytes32(newTotalValue));

        weEthWstEthReserveOracle.updateExchangeRate();
        uint256 newExchangeRate = weEthWstEthReserveOracle.currentExchangeRate();

        uint256 minExchangeRate = exchangeRate - ((exchangeRate * maxChange) / RAY);

        assertLt(newExchangeRate, exchangeRate, "below previous exchange rate");
        assertGt(newExchangeRate, minExchangeRate, "above minimum exchange rate bound");
    }
}
