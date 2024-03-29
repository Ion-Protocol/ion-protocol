// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SwEthHandler_ForkBase } from "../../../fork/concrete/lst/SwEthHandler.t.sol";

import { LstHandler_ForkBase } from "../../../helpers/handlers/LstHandlerForkBase.sol";

import { ISwEth } from "../../../../src/interfaces/ProviderInterfaces.sol";
import { SwellLibrary } from "../../../../src/libraries/lst/SwellLibrary.sol";
import {
    BalancerFlashloanDirectMintHandler_FuzzTest,
    BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest
} from "../handlers-base/BalancerFlashloanDirectMintHandler.t.sol";
import {
    UniswapFlashswapHandler_FuzzTest,
    UniswapFlashswapHandler_WithRateChange_FuzzTest
} from "../handlers-base/UniswapFlashswapHandler.t.sol";

using SwellLibrary for ISwEth;

abstract contract SwEthHandler_ForkFuzzTest is
    SwEthHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_FuzzTest,
    UniswapFlashswapHandler_FuzzTest
{
    function setUp() public virtual override(LstHandler_ForkBase, SwEthHandler_ForkBase) {
        super.setUp();
    }
}

contract SwEthHandler_WithRateChange_ForkFuzzTest is
    SwEthHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest,
    UniswapFlashswapHandler_WithRateChange_FuzzTest
{
    function setUp() public virtual override(LstHandler_ForkBase, SwEthHandler_ForkBase) {
        super.setUp();
        ufConfig.initialDepositLowerBound = 1e13;
        bfdmConfig.initialDepositLowerBound = 4 wei;
    }
}
