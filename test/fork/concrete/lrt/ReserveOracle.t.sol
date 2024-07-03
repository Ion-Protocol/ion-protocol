// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ReserveOracle } from "../../../../src/oracles/reserve/ReserveOracle.sol";
import { RsEthWstEthReserveOracle } from "../../../../src/oracles/reserve/lrt/RsEthWstEthReserveOracle.sol";
import { RswEthWstEthReserveOracle } from "../../../../src/oracles/reserve/lrt/RswEthWstEthReserveOracle.sol";
import { EzEthWethReserveOracle } from "./../../../../src/oracles/reserve/lrt/EzEthWethReserveOracle.sol";
import { WeEthWethReserveOracle } from "./../../../../src/oracles/reserve/lrt/WeEthWethReserveOracle.sol";
import { WadRayMath } from "../../../../src/libraries/math/WadRayMath.sol";
import { UPDATE_COOLDOWN } from "../../../../src/oracles/reserve/ReserveOracle.sol";
import {
    RSETH_LRT_ORACLE,
    RSETH_LRT_DEPOSIT_POOL,
    WSTETH_ADDRESS,
    RSETH,
    ETHX_ADDRESS,
    RSWETH,
    EZETH,
    RENZO_RESTAKE_MANAGER,
    BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK,
    ETHER_FI_LIQUIDITY_POOL_ADDRESS,
    WEETH_ADDRESS
} from "../../../../src/Constants.sol";
import { ReserveOracleSharedSetup } from "../../../helpers/ReserveOracleSharedSetup.sol";
import { StdStorage, stdStorage } from "../../../../lib/forge-safe/lib/forge-std/src/StdStorage.sol";
import { IERC20 } from "../../../../lib/forge-safe/lib/forge-std/src/interfaces/IERC20.sol";
import { RAY } from "../../../../src/libraries/math/WadRayMath.sol";
import { WeEthWstEthReserveOracle } from "../../../../src/oracles/reserve/lrt/WeEthWstEthReserveOracle.sol";
import { EzEthWstEthReserveOracle } from "./../../../../src/oracles/reserve/lrt/EzEthWstEthReserveOracle.sol";

import { ReserveOracleSharedSetup } from "../../../helpers/ReserveOracleSharedSetup.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { console2 } from "forge-std/console2.sol";

uint256 constant LTV = 0.9e27;
uint256 constant MAX_CHANGE = 0.03e27;

using WadRayMath for uint256;

abstract contract ReserveOracle_ForkTest is ReserveOracleSharedSetup {
    using stdStorage for StdStorage;

    ReserveOracle reserveOracle;
    StdStorage stdstore1;

    function testFork_CurrentExchangeRate() public {
        uint256 expectedExchangeRate = _getProtocolExchangeRate();
        uint256 currentExchangeRate = reserveOracle.currentExchangeRate();
        assertEq(currentExchangeRate, expectedExchangeRate, "current exchange rate");

        uint256 exchangeRateInEth = _convertToEth(currentExchangeRate);
        assertGt(exchangeRateInEth, 1 ether, "within reasonable exchange rate minimum bound");
        assertLt(exchangeRateInEth, 1.2 ether, "within reasonable exchange rate upper bound");
    }

    function testFork_GetProtocolExchangeRate() public {
        uint256 exchangeRateInEth = _convertToEth(reserveOracle.getProtocolExchangeRate());
        assertGt(exchangeRateInEth, 1 ether, "within reasonable exchange rate minimum bound");
        assertLt(exchangeRateInEth, 1.2 ether, "within reasonable exchange rate minimum bound");
    }

    function testFork_UpdateExchangeRate() public {
        uint256 expectedExchangeRate = _getProtocolExchangeRate();
        reserveOracle.updateExchangeRate();
        assertEq(reserveOracle.currentExchangeRate(), expectedExchangeRate, "update without bound");
    }

    function testFork_RevertWhen_UpdateIsOnCooldown() public {
        reserveOracle.updateExchangeRate();
        vm.expectRevert(abi.encodeWithSelector(ReserveOracle.UpdateCooldown.selector, block.timestamp));
        reserveOracle.updateExchangeRate();
        uint256 lastUpdated = block.timestamp;

        vm.warp(block.timestamp + UPDATE_COOLDOWN - 1);
        vm.expectRevert(abi.encodeWithSelector(ReserveOracle.UpdateCooldown.selector, lastUpdated));
        reserveOracle.updateExchangeRate();
        lastUpdated = block.timestamp;

        vm.warp(block.timestamp + UPDATE_COOLDOWN);
        reserveOracle.updateExchangeRate();
    }

    function testFork_UpdateExchangeRateMaxBounded() public {
        uint256 expectedMaxBound = getMaxBound();
        _increaseExchangeRate();
        reserveOracle.updateExchangeRate();
        assertEq(reserveOracle.currentExchangeRate(), expectedMaxBound, "exchange rate max bounded");
    }

    function testFork_UpdateExchangeRateMinBounded() public {
        uint256 expectedMinBound = getMinBound();
        _decreaseExchangeRate();
        reserveOracle.updateExchangeRate();
        assertEq(reserveOracle.currentExchangeRate(), expectedMinBound, "exchange rate min bounded");
    }

    // --- Helper Functions ---

    function getMaxBound() public view returns (uint256) {
        uint256 currentExchangeRate = reserveOracle.currentExchangeRate();
        uint256 diff = currentExchangeRate.rayMulDown(MAX_CHANGE);
        return currentExchangeRate + diff;
    }

    function getMinBound() public view returns (uint256) {
        uint256 currentExchangeRate = reserveOracle.currentExchangeRate();
        uint256 diff = currentExchangeRate.rayMulDown(MAX_CHANGE);
        return currentExchangeRate - diff;
    }

    function setERC20Balance(address token, address usr, uint256 amt) public {
        stdstore1.target(token).sig(IERC20(token).balanceOf.selector).with_key(usr).checked_write(amt);
        require(IERC20(token).balanceOf(usr) == amt, "balance not set");
    }

    function _increaseExchangeRate() internal virtual returns (uint256);

    function _decreaseExchangeRate() internal virtual returns (uint256);

    /**
     * @dev converts lending asset denomination to ETH
     * @param amt amount of lending asset
     */
    function _convertToEth(uint256 amt) internal virtual returns (uint256);

    /**
     * @dev The expected protocol exchange rate in lender asset denomination
     */
    function _getProtocolExchangeRate() internal virtual returns (uint256);
}

abstract contract MockEzEth is ReserveOracle_ForkTest {
    bytes32 constant EZETH_TOTAL_SUPPLY_SLOT = 0x0000000000000000000000000000000000000000000000000000000000000035;

    function _increaseExchangeRate() internal override returns (uint256 newExchangeRate) {
        uint256 prevExchangeRate = _getProtocolExchangeRate();
        // effectively doubles the exchange rate by halving the total supply of ezETH
        uint256 existingEzETHSupply = EZETH.totalSupply();
        uint256 newTotalSupply = existingEzETHSupply / 2;
        vm.store(address(EZETH), EZETH_TOTAL_SUPPLY_SLOT, bytes32(newTotalSupply));
        newExchangeRate = _getProtocolExchangeRate();

        require(newExchangeRate > prevExchangeRate, "exchange rate should increase");
    }

    function _decreaseExchangeRate() internal override returns (uint256 newExchangeRate) {
        uint256 prevExchangeRate = _getProtocolExchangeRate();
        // effectively halves the exchange rate by doubling the total supply of ezETH
        uint256 existingEzETHSupply = EZETH.totalSupply();
        uint256 newTotalSupply = existingEzETHSupply * 2;
        vm.store(address(EZETH), EZETH_TOTAL_SUPPLY_SLOT, bytes32(newTotalSupply));
        newExchangeRate = _getProtocolExchangeRate();

        require(newExchangeRate < prevExchangeRate, "exchange rate should decrease");
    }
}

contract RsEthWstEthReserveOracle_ForkTest is ReserveOracle_ForkTest {
    using WadRayMath for uint256;

    bytes32 constant RSETH_TOTAL_SUPPLY_SLOT = 0x0000000000000000000000000000000000000000000000000000000000000035;

    function setUp() public override {
        super.setUp();
        reserveOracle = new RsEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, MAX_CHANGE);
    }

    function _increaseExchangeRate() internal override returns (uint256 newPrice) {
        // effectively doubles the exchange rate by giving ETHx amount equal to
        // rsETH total supply to the deposit pool.
        uint256 prevPrice = RSETH_LRT_ORACLE.rsETHPrice();

        uint256 totalSupply = RSETH.totalSupply();
        setERC20Balance(address(ETHX_ADDRESS), address(RSETH_LRT_DEPOSIT_POOL), totalSupply);

        RSETH_LRT_ORACLE.updateRSETHPrice();

        newPrice = RSETH_LRT_ORACLE.rsETHPrice();
        require(newPrice > prevPrice, "price should increase");
    }

    function _decreaseExchangeRate() internal override returns (uint256 newPrice) {
        uint256 prevPrice = RSETH_LRT_ORACLE.rsETHPrice();

        // effectively halves the exchange rate by doubling the rsETH total supply
        uint256 newTotalSupply = RSETH.totalSupply() * 2;
        vm.store(address(RSETH), RSETH_TOTAL_SUPPLY_SLOT, bytes32(newTotalSupply));

        RSETH_LRT_ORACLE.updateRSETHPrice();

        newPrice = RSETH_LRT_ORACLE.rsETHPrice();
        require(newPrice < prevPrice, "price should decrease");
    }

    function _convertToEth(uint256 amt) internal view override returns (uint256) {
        // wstETH * ETH / wstETH
        return WSTETH_ADDRESS.getStETHByWstETH(amt);
    }

    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return RSETH_LRT_ORACLE.rsETHPrice().wadMulDown(WSTETH_ADDRESS.tokensPerStEth());
    }
}

contract EzEthWstEthReserveOracle_ForkTest is MockEzEth {
    using WadRayMath for uint256;

    function setUp() public override {
        super.setUp();
        reserveOracle = new EzEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, MAX_CHANGE);
    }

    function _convertToEth(uint256 amt) internal view override returns (uint256) {
        return WSTETH_ADDRESS.getStETHByWstETH(amt);
    }

    function _getProtocolExchangeRate() internal view override returns (uint256) {
        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();
        uint256 totalSupply = EZETH.totalSupply();
        uint256 exchangeRateInEth = totalTVL.wadDivDown(totalSupply);
        return exchangeRateInEth.wadMulDown(WSTETH_ADDRESS.tokensPerStEth());
    }
}

contract WeEthWstEthReserveOracleForkTest is ReserveOracle_ForkTest {
    function setUp() public override {
        // blockNumber = 19_079_925;
        super.setUp();
        reserveOracle = new WeEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, MAX_CHANGE);
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

    function _increaseExchangeRate() internal override returns (uint256 newPrice) {
        uint256 prevPrice = WEETH_ADDRESS.getRate();

        // effectively doubles the exchange rate by giving ETHx amount equal to
        // rsETH total supply to the deposit pool.
        uint256 totalValueOutOfLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueOutOfLp();
        uint256 totalValueInLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueInLp();

        uint256 currTotalValue = totalValueInLp + totalValueOutOfLp;
        uint256 newTotalValue = currTotalValue * 2;

        vm.store(address(ETHER_FI_LIQUIDITY_POOL_ADDRESS), EETH_LIQUIDITY_POOL_TOTAL_VALUE_SLOT, bytes32(newTotalValue));

        newPrice = WEETH_ADDRESS.getRate();
        require(newPrice > prevPrice, "price should increase");
    }

    function _decreaseExchangeRate() internal override returns (uint256 newPrice) {
        uint256 prevPrice = WEETH_ADDRESS.getRate();

        // effectively doubles the exchange rate by giving ETHx amount equal to
        // rsETH total supply to the deposit pool.
        uint256 totalValueOutOfLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueOutOfLp();
        uint256 totalValueInLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueInLp();

        uint256 currTotalValue = totalValueInLp + totalValueOutOfLp;
        uint256 newTotalValue = currTotalValue / 2;

        vm.store(address(ETHER_FI_LIQUIDITY_POOL_ADDRESS), EETH_LIQUIDITY_POOL_TOTAL_VALUE_SLOT, bytes32(newTotalValue));

        newPrice = WEETH_ADDRESS.getRate();
        require(newPrice < prevPrice, "price should decrease");
    }

    function _convertToEth(uint256 amt) internal view override returns (uint256) {
        // wstETH * ETH / wstETH
        return WSTETH_ADDRESS.getStETHByWstETH(amt);
    }

    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return WEETH_ADDRESS.getRate().wadMulDown(WSTETH_ADDRESS.tokensPerStEth());
    }
}

contract RswEthWstEthReserveOracle_ForkTest is ReserveOracle_ForkTest {
    bytes32 constant RSWETH_RATE_FIXED_SLOT = 0x0000000000000000000000000000000000000000000000000000000000000095;

    function setUp() public override {
        super.setUp();
        reserveOracle = new RswEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, MAX_CHANGE);
    }

    // --- Slashing Scenario ---
    function _increaseExchangeRate() internal override returns (uint256 newPrice) {
        uint256 prevPrice = RSWETH.getRate();

        vm.store(address(RSWETH), RSWETH_RATE_FIXED_SLOT, bytes32(prevPrice * 2));

        newPrice = RSWETH.getRate();
        require(newPrice > prevPrice, "price should increase");
    }

    function _decreaseExchangeRate() internal override returns (uint256 newPrice) {
        uint256 prevPrice = RSWETH.getRate();

        vm.store(address(RSWETH), RSWETH_RATE_FIXED_SLOT, bytes32(prevPrice / 2));

        newPrice = RSWETH.getRate();
        require(newPrice < prevPrice, "price should decrease");
    }

    function _convertToEth(uint256 amt) internal view override returns (uint256) {
        // wstETH * ETH / wstETH
        return WSTETH_ADDRESS.getStETHByWstETH(amt);
    }

    function _getProtocolExchangeRate() internal view override returns (uint256) {
        return RSWETH.getRate().wadMulDown(WSTETH_ADDRESS.tokensPerStEth());
    }
}

contract EzEthWethReserveOracle_ForkTest is MockEzEth {
    using WadRayMath for uint256;

    function setUp() public override {
        super.setUp();
        reserveOracle = new EzEthWethReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, MAX_CHANGE);
    }

    function _convertToEth(uint256 amt) internal view override returns (uint256) {
        return amt; // `amt` is already WETH
    }

    function _getProtocolExchangeRate() internal view override returns (uint256) {
        (,, uint256 totalTVL) = RENZO_RESTAKE_MANAGER.calculateTVLs();
        uint256 totalSupply = EZETH.totalSupply();
        return totalTVL.wadDivDown(totalSupply);
    }
}

contract MockChainlink {
    using SafeCast for uint256;

    uint256 public exchangeRate;

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, exchangeRate.toInt256(), 0, block.timestamp, 0);
    }

    function setExchangeRate(uint256 _exchangeRate) external returns (uint256) {
        exchangeRate = _exchangeRate;
    }
}

contract WeEthWethReserveOracle_ForkTest is ReserveOracle_ForkTest {
    using SafeCast for int256;

    error MaxTimeFromLastUpdateExceeded(uint256, uint256);

    uint256 public immutable MAX_TIME_FROM_LAST_UPDATE = 87_000; // seconds
    uint256 public immutable GRACE_PERIOD = 3600;

    function setUp() public override {
        super.setUp();
        reserveOracle = new WeEthWethReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, MAX_CHANGE, MAX_TIME_FROM_LAST_UPDATE, GRACE_PERIOD);
    }

    function _getForkRpc() internal override returns (string memory) {
        return vm.envString("BASE_MAINNET_RPC_URL");
    }

    function _convertToEth(uint256 amt) internal view override returns (uint256) {
        return amt;
    }

    function _getProtocolExchangeRate() internal view override returns (uint256) {
        (, int256 ethPerWeEth,, uint256 ethPerWeEthUpdatedAt,) =
            BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK.latestRoundData();
        if (block.timestamp - ethPerWeEthUpdatedAt > MAX_TIME_FROM_LAST_UPDATE) {
            revert MaxTimeFromLastUpdateExceeded(block.timestamp, ethPerWeEthUpdatedAt);
        } else {
            return ethPerWeEth.toUint256(); // [WAD]
        }
    }

    // --- Slashing Scenario ---
    function _increaseExchangeRate() internal override returns (uint256 newPrice) {
        // Replace the Chainlink contract that returns the exchange rate with a
        // new dummy contract that returns a higher exchange rate.
        (, int256 prevExchangeRate,,,) = BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK.latestRoundData();

        MockChainlink chainlink = new MockChainlink();

        vm.etch(address(BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK), address(chainlink).code);

        MockChainlink(address(BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK)).setExchangeRate(1.8e18);

        (, int256 newExchangeRate,,,) = BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK.latestRoundData();

        require(newExchangeRate > prevExchangeRate, "price should increase");
    }

    function _decreaseExchangeRate() internal override returns (uint256 newPrice) {
        (, int256 prevExchangeRate,,,) = BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK.latestRoundData();

        MockChainlink chainlink = new MockChainlink();

        vm.etch(address(BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK), address(chainlink).code);

        MockChainlink(address(BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK)).setExchangeRate(0.5e18);

        (, int256 newExchangeRate,,,) = BASE_WEETH_ETH_EXCHANGE_RATE_CHAINLINK.latestRoundData();

        require(newExchangeRate < prevExchangeRate, "price should decrease");
    }
}
