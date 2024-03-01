// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ReserveOracleSharedSetup } from "../../helpers/ReserveOracleSharedSetup.sol";
import { RsEthWstEthSpotOracle } from "./../../../src/oracles/spot/rsEthWstEthSpotOracle.sol";
import { ReserveOracle } from "./../../../src/oracles/reserve/ReserveOracle.sol";
import { SpotOracle } from "./../../../src/oracles/spot/SpotOracle.sol";
import { RsEthWstEthReserveOracle } from "./../../../src/oracles/reserve/RsEthWstEthReserveOracle.sol";
import { WadRayMath } from "./../../../src/libraries/math/WadRayMath.sol";
import { console2 } from "forge-std/console2.sol";

abstract contract SpotOracle_ForkTest is ReserveOracleSharedSetup {
    using WadRayMath for uint256;

    ReserveOracle reserveOracle;
    SpotOracle spotOracle;

    function testFork_ViewPrice() public {
        uint256 price = spotOracle.getPrice();
        console2.log("price", price);
        assertGt(price, 0, "price greater than zero");
    }

    function testFork_ViewSpot() public {
        uint256 price = spotOracle.getPrice();
        uint256 ltv = spotOracle.LTV();
        uint256 expectedSpot = ltv.wadMulDown(price);
        uint256 spot = spotOracle.getSpot();
        console2.log("spot", spot);
        assertEq(spot, expectedSpot, "spot");
    }

    function testFork_UsesPriceAsMin() public {
        // manipulate currentExchangeRate up
    }

    function testFork_PriceIncreasesUsesExchangeRateAsMin() public { }

    function testFork_ExchangeRateDecreasesUsesExchangeRateAsMin() public { }

    function testFork_MaxTimeFromLastUpdateExceeded() public { }

    function testFork_MaxTimeFromLastUpdateNotExceeded() public { }
}

contract RsEthWstEthSpotOracle_ForkTest is SpotOracle_ForkTest {
    uint256 constant MAX_TIME_FROM_LAST_UPDATE = 87_000;
    uint256 constant MAX_LTV = 0.8e27;

    function setUp() public override {
        super.setUp();
        reserveOracle = new RsEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, MAX_CHANGE);
        spotOracle = new RsEthWstEthSpotOracle(MAX_LTV, address(reserveOracle), MAX_TIME_FROM_LAST_UPDATE);
    }
}
