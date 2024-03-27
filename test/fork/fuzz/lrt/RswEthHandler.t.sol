// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RswEthHandler_ForkBase } from "../../concrete/lrt/RswEthHandler.t.sol";
import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";
import {
    UniswapFlashswapDirectMintHandler_FuzzTest,
    UniswapFlashswapDirectMintHandler_WithRateChange_FuzzTest
} from "../handlers-base/UniswapFlashswapDirectMintHandler.t.sol";
import { RSWETH } from "../../../../src/Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

abstract contract RswEthHandler_ForkFuzzTest is RswEthHandler_ForkBase, UniswapFlashswapDirectMintHandler_FuzzTest {
    function setUp() public virtual override(LrtHandler_ForkBase, RswEthHandler_ForkBase) {
        super.setUp();
    }
}

contract RswEthHandler_WithRateChange_ForkFuzzTest is
    RswEthHandler_ForkFuzzTest,
    UniswapFlashswapDirectMintHandler_WithRateChange_FuzzTest
{
    function setUp() public override(LrtHandler_ForkBase, RswEthHandler_ForkFuzzTest) {
        super.setUp();
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = RSWETH;
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
        depositContracts[0] = address(RSWETH);
    }
}
