// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WeEthHandler_ForkBase } from "../concrete/WeEthHandlerFork.t.sol";
import { WeEthIonHandler_ForkBase } from "../../helpers/weETH/WeEthIonHandlerForkBase.sol";
import {
    UniswapFlashswapDirectMintHandler_FuzzTest,
    UniswapFlashswapDirectMintHandler_WithRateChange_FuzzTest
} from "./handlers-base/UniswapFlashswapDirectMintHandler.t.sol";

abstract contract WeEthHandler_ForkFuzzTest is WeEthHandler_ForkBase, UniswapFlashswapDirectMintHandler_FuzzTest {
    function setUp() public virtual override(WeEthHandler_ForkBase, WeEthIonHandler_ForkBase) {
        super.setUp();
    }
}

contract WeEthHanlder_WithRateChange_ForkFuzzTest is
    WeEthHandler_ForkFuzzTest,
    UniswapFlashswapDirectMintHandler_WithRateChange_FuzzTest
{
    function setUp() public override(WeEthHandler_ForkFuzzTest, WeEthIonHandler_ForkBase) {
        super.setUp();
        ufdmConfig.initialDepositLowerBound = 4 wei;
    }
}
