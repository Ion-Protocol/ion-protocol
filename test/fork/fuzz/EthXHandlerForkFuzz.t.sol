// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { EthXHandler_ForkBase } from "../../fork/concrete/EthXHandlerFork.t.sol";

import { WadRayMath } from "../../../src/libraries/math/WadRayMath.sol";
import { IStaderStakePoolsManager } from "../../../src/interfaces/ProviderInterfaces.sol";
import { StaderLibrary } from "../../../src/libraries/StaderLibrary.sol";
import { IonHandler_ForkBase } from "../../helpers/IonHandlerForkBase.sol";
import {
    BalancerFlashloanDirectMintHandler_FuzzTest,
    BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest
} from "./handlers-base/BalancerFlashloanDirectMintHandler.t.sol";
import {
    UniswapFlashswapHandler_FuzzTest,
    UniswapFlashswapHandler_WithRateChange_FuzzTest
} from "./handlers-base/UniswapFlashswapHandler.t.sol";
import {
    UniswapFlashloanBalancerSwapHandler_FuzzTest,
    UniswapFlashloanBalancerSwapHandler_WithRateChange_FuzzTest
} from "./handlers-base/UniswapFlashloanBalancerSwapHandler.t.sol";

using StaderLibrary for IStaderStakePoolsManager;

abstract contract EthXHandler_ForkFuzzTest is
    EthXHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_FuzzTest,
    UniswapFlashloanBalancerSwapHandler_FuzzTest,
    UniswapFlashswapHandler_FuzzTest
{
    using WadRayMath for *;

    uint256 minDeposit;
    uint256 maxDeposit;

    function setUp() public virtual override(EthXHandler_ForkBase, IonHandler_ForkBase) {
        super.setUp();

        minDeposit = MAINNET_STADER.staderConfig().getMinDepositAmount();
        maxDeposit = MAINNET_STADER.staderConfig().getMaxDepositAmount();
    }
}

contract EthXHandler_WithRateChange_ForkFuzzTest is
    EthXHandler_ForkFuzzTest,
    BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest,
    UniswapFlashloanBalancerSwapHandler_WithRateChange_FuzzTest,
    UniswapFlashswapHandler_WithRateChange_FuzzTest
{
    function setUp() public override(EthXHandler_ForkFuzzTest, IonHandler_ForkBase) {
        super.setUp();
        ufbsConfig.initialDepositLowerBound = minDeposit;
        ufConfig.initialDepositLowerBound = minDeposit;
        bfdmConfig.initialDepositLowerBound = minDeposit;
    }
}
