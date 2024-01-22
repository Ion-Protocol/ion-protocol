// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { SwEthHandler_ForkBase } from "../../fork/concrete/SwEthHandlerFork.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { WadRayMath, WAD, RAY } from "../../../src/libraries/math/WadRayMath.sol";
import { ISwEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { SwellLibrary } from "../../../src/libraries/SwellLibrary.sol";
import { IonHandler_ForkBase } from "../../helpers/IonHandlerForkBase.sol";
import {
    BalancerFlashloanDirectMintHandler_FuzzTest,
    BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest
} from "./handlers-base/BalancerFlashloanDirectMintHandler.t.sol";
import {
    UniswapFlashswapHandler_FuzzTest,
    UniswapFlashswapHandler_WithRateChange_FuzzTest
} from "./handlers-base/UniswapFlashswapHandler.t.sol";

import { Vm } from "forge-std/Vm.sol";

using SwellLibrary for ISwEth;

abstract contract SwEthHandler_ForkFuzzTest is
    SwEthHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest,
    UniswapFlashswapHandler_WithRateChange_FuzzTest
{
    using WadRayMath for *;

    function setUp() public virtual override(IonHandler_ForkBase, SwEthHandler_ForkBase) {
        super.setUp();
    }
}

contract SwEthHandler_WithRateChange_ForkFuzzTest is
    SwEthHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_WithRateChange_FuzzTest,
    UniswapFlashswapHandler_WithRateChange_FuzzTest
{
    function setUp() public virtual override(IonHandler_ForkBase, SwEthHandler_ForkBase) {
        super.setUp();
        ufConfig.initialDepositLowerBound = 1e13;
        bfdmConfig.initialDepositLowerBound = 4 wei;
    }
}
