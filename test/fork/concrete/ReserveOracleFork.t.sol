// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ReserveOracle } from "./../../../src/oracles/reserve/ReserveOracle.sol";
import { RsEthWstEthSpotOracle } from "./../../../src/oracles/spot/rsEthWstEthSpotOracle.sol";
import { RsEthWstEthReserveOracle } from "./../../../src/oracles/reserve/RsEthWstEthReserveOracle.sol";
import { WadRayMath } from "./../../../src/libraries/math/WadRayMath.sol";
import { UPDATE_COOLDOWN } from "./../../../src/oracles/reserve/ReserveOracle.sol";
import {
    RSETH_LRT_ORACLE,
    RSETH_LRT_DEPOSIT_POOL,
    WSTETH_ADDRESS,
    RSETH,
    STETH_ADDRESS,
    ETHX_ADDRESS
} from "../../../src/Constants.sol";
import { ReserveOracleSharedSetup } from "../../helpers/ReserveOracleSharedSetup.sol";
import { StdStorage, stdStorage } from "./../../../lib/forge-safe/lib/forge-std/src/StdStorage.sol";
import { IERC20 } from "./../../../lib/forge-safe/lib/forge-std/src/interfaces/IERC20.sol";
import { console2 } from "forge-std/console2.sol";

uint256 constant LTV = 0.9e27;
uint256 constant MAX_CHANGE = 0.03e27;

abstract contract ReserveOracle_ForkTest is ReserveOracleSharedSetup {
    using stdStorage for StdStorage;
    using WadRayMath for uint256;

    ReserveOracle reserveOracle;
    StdStorage stdstore1;

    function testFork_CurrentExchangeRate() public {
        uint256 expectedExchangeRate = getProtocolExchangeRate();
        uint256 currentExchangeRate = reserveOracle.currentExchangeRate();
        assertEq(currentExchangeRate, expectedExchangeRate, "current exchange rate");

        uint256 exchangeRateInEth = convertToEth(currentExchangeRate);
        assertGt(exchangeRateInEth, 1 ether, "within reasonable exchange rate minimum bound");
        assertLt(exchangeRateInEth, 1.2 ether, "within reasonable exchange rate upper bound");
    }

    function testFork_GetProtocolExchangeRate() public {
        uint256 exchangeRateInEth = convertToEth(reserveOracle.getProtocolExchangeRate());
        assertGt(exchangeRateInEth, 1 ether, "within reasonable exchange rate minimum bound");
        assertLt(exchangeRateInEth, 1.2 ether, "within reasonable exchange rate minimum bound");
    }

    function testFork_UpdateExchangeRate() public {
        uint256 expectedExchangeRate = getProtocolExchangeRate();
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
        increaseExchangeRate();
        reserveOracle.updateExchangeRate();
        assertEq(reserveOracle.currentExchangeRate(), expectedMaxBound, "exchange rate max bounded");
    }

    function testFork_UpdateExchangeRateMinBounded() public {
        uint256 expectedMinBound = getMinBound();
        decreaseExchangeRate();
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

    function increaseExchangeRate() public virtual returns (uint256) { }

    function decreaseExchangeRate() public virtual returns (uint256) { }

    // converts lending asset denomination to ETH
    function convertToEth(uint256 amt) public virtual returns (uint256) { }

    function getProtocolExchangeRate() public virtual returns (uint256) { }
}

contract RsEthWstEthReserveOracle_ForkTest is ReserveOracle_ForkTest {
    using WadRayMath for uint256;

    bytes32 constant RSETH_TOTAL_SUPPLY_SLOT = 0x0000000000000000000000000000000000000000000000000000000000000035;

    function setUp() public override {
        super.setUp();
        reserveOracle = new RsEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, MAX_CHANGE);
    }

    function increaseExchangeRate() public override returns (uint256 newPrice) {
        // effectively doubles the exchange rate by giving ETHx amount equal to
        // rsETH total supply to the deposit pool.
        uint256 prevPrice = RSETH_LRT_ORACLE.rsETHPrice();

        uint256 totalSupply = RSETH.totalSupply();
        setERC20Balance(address(ETHX_ADDRESS), address(RSETH_LRT_DEPOSIT_POOL), totalSupply);

        RSETH_LRT_ORACLE.updateRSETHPrice();

        newPrice = RSETH_LRT_ORACLE.rsETHPrice();
        require(newPrice > prevPrice, "price should increase");
    }

    function decreaseExchangeRate() public override returns (uint256 newPrice) {
        uint256 prevPrice = RSETH_LRT_ORACLE.rsETHPrice();

        // effectivly halves the exchange rate by doubling the rsETH total supply
        uint256 newTotalSupply = RSETH.totalSupply() * 2;
        vm.store(address(RSETH), RSETH_TOTAL_SUPPLY_SLOT, bytes32(newTotalSupply));

        RSETH_LRT_ORACLE.updateRSETHPrice();

        newPrice = RSETH_LRT_ORACLE.rsETHPrice();
        require(newPrice < prevPrice, "price should decrease");
    }

    function convertToEth(uint256 amt) public view override returns (uint256) {
        // wstETH * ETH / wstETH
        return WSTETH_ADDRESS.getStETHByWstETH(amt);
    }

    function getProtocolExchangeRate() public view override returns (uint256) {
        return RSETH_LRT_ORACLE.rsETHPrice().wadMulDown(WSTETH_ADDRESS.tokensPerStEth());
    }
}
