// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { EzEthHandler_ForkBase } from "../../concrete/lrt/EzEthHandler.t.sol";
import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";
import {
    UniswapFlashswapDirectMintHandlerWithDust_FuzzTest,
    UniswapFlashswapDirectMintHandlerWithDust_WithRateChange_FuzzTest
} from "../handlers-base/UniswapFlashswapDirectMintHandlerWithDust.t.sol";
import { EZETH } from "../../../../src/Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract EzEthHandler_ForkFuzzTest is
    EzEthHandler_ForkBase,
    UniswapFlashswapDirectMintHandlerWithDust_FuzzTest
{
    function setUp() public virtual override(LrtHandler_ForkBase, EzEthHandler_ForkBase) {
        super.setUp();
    }
}

contract EzEthHandler_WithRateChange_ForkFuzzTest is
    EzEthHandler_ForkFuzzTest,
    UniswapFlashswapDirectMintHandlerWithDust_WithRateChange_FuzzTest
{
    function setUp() public override(LrtHandler_ForkBase, EzEthHandler_ForkFuzzTest) {
        super.setUp();
        ufdmConfig.initialDepositLowerBound = 4 wei;
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = EZETH;
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
        depositContracts[0] = address(EZETH);
    }
}
