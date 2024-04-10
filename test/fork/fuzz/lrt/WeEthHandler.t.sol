// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WeEthHandler_ForkBase } from "../../concrete/lrt/WeEthHandler.t.sol";
import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";
import {
    UniswapFlashswapDirectMintHandler_FuzzTest,
    UniswapFlashswapDirectMintHandler_WithRateChange_FuzzTest
} from "../handlers-base/UniswapFlashswapDirectMintHandler.t.sol";
import { WEETH_ADDRESS } from "../../../../src/Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract WeEthHandler_ForkFuzzTest is WeEthHandler_ForkBase, UniswapFlashswapDirectMintHandler_FuzzTest {
    function setUp() public virtual override(LrtHandler_ForkBase, WeEthHandler_ForkBase) {
        super.setUp();
    }
}

contract WeEthHandler_WithRateChange_ForkFuzzTest is
    WeEthHandler_ForkFuzzTest,
    UniswapFlashswapDirectMintHandler_WithRateChange_FuzzTest
{
    function setUp() public override(LrtHandler_ForkBase, WeEthHandler_ForkFuzzTest) {
        super.setUp();
        ufdmConfig.initialDepositLowerBound = 4 wei;
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = WEETH_ADDRESS;
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
        depositContracts[0] = address(WEETH_ADDRESS);
    }
}
