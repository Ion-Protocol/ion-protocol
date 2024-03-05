// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RsEthHandler_ForkBase } from "../concrete/RsEthHandlerFork.t.sol";
import { LrtHandler_ForkBase } from "../../helpers/handlers/LrtHandlerForkBase.sol";
import {
    UniswapFlashswapDirectMintHandler_FuzzTest,
    UniswapFlashswapDirectMintHandler_WithRateChange_FuzzTest
} from "./handlers-base/UniswapFlashswapDirectMintHandler.t.sol";
import { RSETH, RSETH_LRT_DEPOSIT_POOL } from "../../../src/Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract RsEthHandler_ForkFuzzTest is RsEthHandler_ForkBase, UniswapFlashswapDirectMintHandler_FuzzTest {
    function setUp() public virtual override(LrtHandler_ForkBase, RsEthHandler_ForkBase) {
        super.setUp();
    }
}

contract RsEthHandler_WithRateChange_ForkFuzzTest is
    RsEthHandler_ForkFuzzTest,
    UniswapFlashswapDirectMintHandler_WithRateChange_FuzzTest
{
    function setUp() public override(LrtHandler_ForkBase, RsEthHandler_ForkFuzzTest) {
        super.setUp();
        ufdmConfig.initialDepositLowerBound = RSETH_LRT_DEPOSIT_POOL.minAmountToDeposit();
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = RSETH;
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
        depositContracts[0] = address(RSETH_LRT_DEPOSIT_POOL);
    }
}
