// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SpotOracle } from "./../../../src/oracles/spot/SpotOracle.sol";
import { ReserveOracle } from "./../../../src/oracles/reserve/ReserveOracle.sol";
import { RsEthWstEthSpotOracle } from "./../../../src/oracles/spot/rsEthWstEthSpotOracle.sol";
import { RsEthWstEthReserveOracle } from "./../../../src/oracles/reserve/RsEthWstEthReserveOracle.sol";
import { ReserveOracleSharedSetup } from "../../helpers/ReserveOracleSharedSetup.sol";
import { WadRayMath } from "./../../../src/libraries/math/WadRayMath.sol";
import { console2 } from "forge-std/console2.sol";
import {
    RSETH_LRT_ORACLE,
    RSETH_LRT_DEPOSIT_POOL,
    WSTETH_ADDRESS,
    RSETH,
    STETH_ADDRESS,
    ETHX_ADDRESS
} from "../../../src/Constants.sol";
import { StdStorage, stdStorage } from "./../../../lib/forge-safe/lib/forge-std/src/StdStorage.sol";
import { IERC20 } from "./../../../lib/forge-safe/lib/forge-std/src/interfaces/IERC20.sol";

uint256 constant LTV = 0.9e27;
uint256 constant MAX_CHANGE = 0.03e27;

abstract contract ReserveOracle_ForkTest is ReserveOracleSharedSetup {
    using stdStorage for StdStorage;
    using WadRayMath for uint256;

    ReserveOracle reserveOracle;
    StdStorage stdstore1;

    function testFork_CurrentExchangeRate() public {
        uint256 exchangeRateInEth = convertToEth(reserveOracle.currentExchangeRate());
        console2.log("exchangeRateInEth", exchangeRateInEth);
        assertGt(exchangeRateInEth, 1 ether, "exchange rate min bound");
        assertLt(exchangeRateInEth, 1.2 ether, "exchange rate upper bound");
    }

    function testFork_GetProtocolExchangeRate() public {
        uint256 exchangeRateInEth = convertToEth(reserveOracle.getProtocolExchangeRate());
        assertGt(exchangeRateInEth, 1 ether, "exchange rate min bound");
        assertLt(exchangeRateInEth, 1.2 ether, "exchange rate upper bound");
    }

    function testFork_RevertWhen_UpdateIsOnCooldown() public {
        reserveOracle.updateExchangeRate();
        vm.expectRevert(abi.encodeWithSelector(ReserveOracle.UpdateCooldown.selector, block.timestamp));
        reserveOracle.updateExchangeRate();
    }

    function testFork_UpdateExchangeRate() public {
        uint256 expectedExchangeRate = protocolExchangeRate();
        reserveOracle.updateExchangeRate();
        assertEq(reserveOracle.currentExchangeRate(), expectedExchangeRate, "update without bound");
    }

    function testFork_ExchangeRateGoesDown() public {
        setERC20Balance(address(ETHX_ADDRESS), RSETH_LRT_DEPOSIT_POOL, 1e18);
    }

    function testFork_ExchangeRateGoesUp() public { }

    function testFork_UpdateExchangeRateMaxBounded() public { }

    function testFork_UpdateExchangeRateMinBounded() public { }

    // --- Helper Functions ---

    function changeExchangeRate() public virtual { }

    // converts lending asset denomination to ETH
    function convertToEth(uint256 amt) public virtual returns (uint256) { }

    function protocolExchangeRate() public virtual returns (uint256) { }

    function setERC20Balance(address token, address usr, uint256 amt) public {
        stdstore1.target(token).sig(IERC20(token).balanceOf.selector).with_key(usr).checked_write(amt);
        require(IERC20(token).balanceOf(usr) == amt, "balance not set");
    }
}

contract RsEthWstEthReserveOracle_ForkTest is ReserveOracle_ForkTest {
    using WadRayMath for uint256;

    function setUp() public override {
        super.setUp();
        reserveOracle = new RsEthWstEthReserveOracle(ILK_INDEX, emptyFeeds, QUORUM, MAX_CHANGE);
    }

    function changeExchangeRate() public override {
        // manipulate balanceOf for wstEdTH
    }

    function convertToEth(uint256 amt) public view override returns (uint256) {
        // wstETH * ETH / wstETH
        return WSTETH_ADDRESS.getStETHByWstETH(amt);
    }

    function protocolExchangeRate() public view override returns (uint256) {
        return RSETH_LRT_ORACLE.rsETHPrice().wadMulDown(WSTETH_ADDRESS.tokensPerStEth());
    }
}
