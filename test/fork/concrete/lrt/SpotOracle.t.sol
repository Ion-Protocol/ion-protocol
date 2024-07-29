// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ReserveOracle } from "../../../../src/oracles/reserve/ReserveOracle.sol";
import { SpotOracle } from "../../../../src/oracles/spot/SpotOracle.sol";
import { RsEthWstEthReserveOracle } from "../../../../src/oracles/reserve/lrt/RsEthWstEthReserveOracle.sol";
import { RsEthWstEthSpotOracle } from "../../../../src/oracles/spot/lrt/RsEthWstEthSpotOracle.sol";
import { RswEthWstEthReserveOracle } from "../../../../src/oracles/reserve/lrt/RswEthWstEthReserveOracle.sol";
import { RswEthWstEthSpotOracle } from "../../../../src/oracles/spot/lrt/RswEthWstEthSpotOracle.sol";
import { WeEthWstEthReserveOracle } from "../../../../src/oracles/reserve/lrt/WeEthWstEthReserveOracle.sol";
import { WeEthWstEthSpotOracle } from "../../../../src/oracles/spot/lrt/WeEthWstEthSpotOracle.sol";
import { EzEthWstEthReserveOracle } from "./../../../../src/oracles/reserve/lrt/EzEthWstEthReserveOracle.sol";
import { EzEthWstEthSpotOracle } from "./../../../../src/oracles/spot/lrt/EzEthWstEthSpotOracle.sol";
import { EzEthWethReserveOracle } from "./../../../../src/oracles/reserve/lrt/EzEthWethReserveOracle.sol";
import { EzEthWethSpotOracle } from "./../../../../src/oracles/spot/lrt/EzEthWethSpotOracle.sol";
import { WadRayMath } from "../../../../src/libraries/math/WadRayMath.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { ReserveOracleSharedSetup } from "../../../helpers/ReserveOracleSharedSetup.sol";

abstract contract SpotOracle_ForkTest is ReserveOracleSharedSetup {
    using WadRayMath for uint256;

    bytes32 constant CURRENT_EXCHANGE_RATE_SLOT = 0;

    ReserveOracle reserveOracle;
    SpotOracle spotOracle;

    function testFork_ViewPrice() public virtual {
        uint256 price = spotOracle.getPrice();
        assertGt(price, 0, "price greater than zero");
    }

    function testFork_ViewSpot() public {
        uint256 ltv = spotOracle.LTV();

        uint256 price = spotOracle.getPrice();
        uint256 currentExchangeRate = reserveOracle.currentExchangeRate();

        uint256 min = Math.min(price, currentExchangeRate);

        uint256 expectedSpot = ltv.wadMulDown(min);
        uint256 spot = spotOracle.getSpot();

        assertEq(spot, expectedSpot, "spot");
    }

    function testFork_UsesPriceAsMin() public {
        uint256 price = spotOracle.getPrice();
        uint256 ltv = spotOracle.LTV();
        uint256 higherExchangeRate = price.wadMulDown(1.5e18);
        uint256 expectedSpot = ltv.wadMulDown(price);

        setCurrentExchangeRate(higherExchangeRate);
        assertEq(spotOracle.getSpot(), expectedSpot, "uses price as min");
    }

    function testFork_UsesExchangeRateAsMin() public {
        uint256 price = spotOracle.getPrice();
        uint256 ltv = spotOracle.LTV();
        uint256 lowerExchangeRate = price.wadMulDown(0.5e18);
        uint256 expectedSpot = ltv.wadMulDown(lowerExchangeRate);

        setCurrentExchangeRate(lowerExchangeRate);
        assertEq(spotOracle.getSpot(), expectedSpot, "uses exchange rate as min");
    }

    function testFork_MaxTimeFromLastUpdateExceeded() public virtual {
        assertGt(spotOracle.getPrice(), 0, "time from last update not exceeded price should not be zero");
        assertGt(spotOracle.getSpot(), 0, "time from last update not exceeded spot should not be zero");

        vm.warp(block.timestamp + 2 days);

        assertEq(spotOracle.getPrice(), 0, "time from last update exceeded price should be zero");
        assertEq(spotOracle.getSpot(), 0, "time from last update exceeded spot should be zero");
    }

    function setCurrentExchangeRate(uint256 exchangeRate) public {
        vm.store(address(reserveOracle), CURRENT_EXCHANGE_RATE_SLOT, bytes32(exchangeRate));
        require(reserveOracle.currentExchangeRate() == exchangeRate, "set current exchange rate");
    }
}

contract WeEthWstEthSpotOracle_ForkTest is SpotOracle_ForkTest {
    uint256 constant MAX_TIME_FROM_LAST_UPDATE = 87_000;
    uint256 constant MAX_LTV = 0.8e27;

    function setUp() public override {
        super.setUp();
        reserveOracle = new WeEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, DEFAULT_MAX_CHANGE);
        spotOracle = new WeEthWstEthSpotOracle(MAX_LTV, address(reserveOracle), MAX_TIME_FROM_LAST_UPDATE);
    }
}

contract RsEthWstEthSpotOracle_ForkTest is SpotOracle_ForkTest {
    uint256 constant MAX_TIME_FROM_LAST_UPDATE = 87_000;
    uint256 constant MAX_LTV = 0.8e27;

    function setUp() public override {
        super.setUp();
        reserveOracle = new RsEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, DEFAULT_MAX_CHANGE);
        spotOracle = new RsEthWstEthSpotOracle(MAX_LTV, address(reserveOracle), MAX_TIME_FROM_LAST_UPDATE);
    }
}

contract RswEthWstEthSpotOracle_ForkTest is SpotOracle_ForkTest {
    uint256 constant MAX_TIME_FROM_LAST_UPDATE = 87_000;
    uint256 constant MAX_LTV = 0.8e27;

    function setUp() public override {
        super.setUp();
        reserveOracle = new RswEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, DEFAULT_MAX_CHANGE);
        spotOracle = new RswEthWstEthSpotOracle(MAX_LTV, address(reserveOracle), MAX_TIME_FROM_LAST_UPDATE);
    }
}

contract EzEthWstEthSpotOracle_ForkTest is SpotOracle_ForkTest {
    uint256 constant MAX_TIME_FROM_LAST_UPDATE = 87_000;
    uint256 constant MAX_LTV = 0.8e27;

    function setUp() public override {
        super.setUp();
        reserveOracle = new EzEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, DEFAULT_MAX_CHANGE);
        spotOracle = new EzEthWstEthSpotOracle(MAX_LTV, address(reserveOracle), MAX_TIME_FROM_LAST_UPDATE);
    }
}

contract EzEthWethSpotOracle_ForkTest is SpotOracle_ForkTest {
    uint256 constant MAX_TIME_FROM_LAST_UPDATE = 87_000;
    uint256 constant MAX_LTV = 0.8e27;

    function setUp() public override {
        super.setUp();
        reserveOracle = new EzEthWethReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, DEFAULT_MAX_CHANGE);
        spotOracle = new EzEthWethSpotOracle(MAX_LTV, address(reserveOracle), MAX_TIME_FROM_LAST_UPDATE);
    }
}
