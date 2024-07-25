// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RsEthWethHandler_ForkTest } from "../../concrete/lrt/BaseMainnet/RsEthWethHandler.t.sol";
import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";
import {
    AerodromeFlashswapHandler_FuzzTest,
    AerodromeFlashswapHandler_WithRateChange_FuzzTest
} from "../handlers-base/AerodromeFlashswapHandler.t.sol";
import { 
    BASE_RSETH_WETH_AERODROME,
    BASE_WETH,
    BASE_RSETH,
    BASE_RSETH_ETH_PRICE_CHAINLINK,
    RSETH_LRT_DEPOSIT_POOL
} from "../../../../src/Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract RsEthWethHandler_ForkFuzzTest is RsEthWethHandler_ForkTest, AerodromeFlashswapHandler_FuzzTest {
    function setUp() public virtual override(LrtHandler_ForkBase, RsEthWethHandler_ForkTest) {
        super.setUp();
    }
}

contract RsEthWethHandler_WithRateChange_ForkFuzzTest is
    RsEthWethHandler_ForkTest,
    AerodromeFlashswapHandler_WithRateChange_FuzzTest
{
    function setUp() public override(LrtHandler_ForkBase, RsEthWethHandler_ForkFuzzTest) {
        super.setUp();
        ufdmConfig.initialDepositLowerBound = RSETH_LRT_DEPOSIT_POOL.minAmountToDeposit();
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = BASE_RSETH;
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
        depositContracts[0] = address(RSETH_LRT_DEPOSIT_POOL);
    }
}