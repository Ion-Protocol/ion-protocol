// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { PT_WEETH_POOL, PT_RSETH_POOL, PT_EZETH_POOL, PT_RSWETH_POOL } from "../../../../src/Constants.sol";
import { PtSpotOracle } from "../../../../src/oracles/spot/PtSpotOracle.sol";
import { WeEthPtReserveOracle } from "../../../../src/oracles/reserve/pendle/WeEthPtReserveOracle.sol";
import { RsEthPtReserveOracle } from "../../../../src/oracles/reserve/pendle/RsEthPtReserveOracle.sol";
import { EzEthPtReserveOracle } from "../../../../src/oracles/reserve/pendle/EzEthPtReserveOracle.sol";
import { RswEthPtReserveOracle } from "../../../../src/oracles/reserve/pendle/RswEthPtReserveOracle.sol";

import { SpotOracle_ForkTest } from "../lrt/SpotOracle.t.sol";

uint256 constant MAX_TIME_FROM_LAST_UPDATE = 87_000;
uint256 constant MAX_LTV = 0.8e27;
uint32 constant TWAP_DURATION = 1800;

abstract contract PtSpotOracle_ForkTest is SpotOracle_ForkTest {
    function testFork_MaxTimeFromLastUpdateExceeded() public override { }
}

contract WeEthPtSpotOracle_ForkTest is PtSpotOracle_ForkTest {
    function setUp() public override {
        super.setUp();
        reserveOracle = new WeEthPtReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, DEFAULT_MAX_CHANGE);
        spotOracle = new PtSpotOracle(PT_WEETH_POOL, TWAP_DURATION, MAX_LTV, address(reserveOracle));
    }
}

contract RsEthPtSpotOracle_ForkTest is PtSpotOracle_ForkTest {
    function setUp() public override {
        super.setUp();
        reserveOracle = new RsEthPtReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, DEFAULT_MAX_CHANGE);
        spotOracle = new PtSpotOracle(PT_RSETH_POOL, TWAP_DURATION, MAX_LTV, address(reserveOracle));
    }
}

contract EzEthPtSpotOracle_ForkTest is PtSpotOracle_ForkTest {
    function setUp() public override {
        super.setUp();
        reserveOracle = new EzEthPtReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, DEFAULT_MAX_CHANGE);
        spotOracle = new PtSpotOracle(PT_EZETH_POOL, TWAP_DURATION, MAX_LTV, address(reserveOracle));
    }
}

contract RswEthPtSpotOracle_ForkTest is PtSpotOracle_ForkTest {
    function setUp() public override {
        super.setUp();
        reserveOracle = new RswEthPtReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, DEFAULT_MAX_CHANGE);
        spotOracle = new PtSpotOracle(PT_RSWETH_POOL, TWAP_DURATION, MAX_LTV, address(reserveOracle));
    }
}
