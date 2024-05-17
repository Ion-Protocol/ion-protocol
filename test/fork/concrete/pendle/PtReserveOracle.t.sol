// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { EzEthPtReserveOracle } from "../../../../src/oracles/reserve/pendle/EzEthPtReserveOracle.sol";
import { RsEthPtReserveOracle } from "../../../../src/oracles/reserve/pendle/RsEthPtReserveOracle.sol";
import { RswEthPtReserveOracle } from "../../../../src/oracles/reserve/pendle/RswEthPtReserveOracle.sol";
import { WeEthPtReserveOracle } from "../../../../src/oracles/reserve/pendle/WeEthPtReserveOracle.sol";

contract PtReserveOracleTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
    }

    function test_WeEth() public {
        WeEthPtReserveOracle reserveOracle = new WeEthPtReserveOracle(0, new address[](3), 0, 0.02e18);
        assertLe(reserveOracle.getProtocolExchangeRate(), 1e18);
    }

    function test_RsEth() public {
        RsEthPtReserveOracle reserveOracle = new RsEthPtReserveOracle(0, new address[](3), 0, 0.02e18);
        assertLe(reserveOracle.getProtocolExchangeRate(), 1e18);
    }

    function test_RswEth() public {
        RswEthPtReserveOracle reserveOracle = new RswEthPtReserveOracle(0, new address[](3), 0, 0.02e18);
        assertLe(reserveOracle.getProtocolExchangeRate(), 1e18);
    }

    function test_EzEth() public {
        EzEthPtReserveOracle reserveOracle = new EzEthPtReserveOracle(0, new address[](3), 0, 0.02e18);
        assertLe(reserveOracle.getProtocolExchangeRate(), 1e18);
    }
}
