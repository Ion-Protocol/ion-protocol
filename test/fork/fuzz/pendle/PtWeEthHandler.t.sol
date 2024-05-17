// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandler_ForkBase } from "../../../helpers/handlers/IonHandlerForkBase.sol";
import { PtHandler_ForkBase } from "../../../helpers/handlers/PtHandlerBase.sol";
import { PtWeEthHandler_ForkBase } from "../../concrete/pendle/PtWeEthHandler.t.sol";
import { PtHandler_FuzzTest, PtHandler_WithRateChange_FuzzTest } from "../handlers-base/PtHandler.t.sol";
import { PT_WEETH_POOL } from "../../../../src/Constants.sol";

import { IPPrincipalToken } from "pendle-core-v2-public/interfaces/IPPrincipalToken.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract PtWeEthHandler_ForkFuzzTest is PtWeEthHandler_ForkBase, PtHandler_FuzzTest {
    function setUp() public virtual override(PtHandler_ForkBase, PtWeEthHandler_ForkBase) {
        super.setUp();
    }

    function _getUnderlying()
        internal
        pure
        virtual
        override(IonHandler_ForkBase, PtWeEthHandler_ForkBase)
        returns (address)
    {
        return PtWeEthHandler_ForkBase._getUnderlying();
    }
}

contract PtWeEthHandler_WithRateChange_ForkFuzzTest is
    PtWeEthHandler_ForkFuzzTest,
    PtHandler_WithRateChange_FuzzTest
{
    function setUp() public override(PtHandler_ForkBase, PtWeEthHandler_ForkFuzzTest) {
        super.setUp();
    }

    function _getUnderlying()
        internal
        pure
        override(IonHandler_ForkBase, PtWeEthHandler_ForkFuzzTest)
        returns (address)
    {
        return PtWeEthHandler_ForkBase._getUnderlying();
    }

    function _getCollaterals() internal view override returns (IERC20[] memory _collaterals) {
        (, IPPrincipalToken _pt,) = PT_WEETH_POOL.readTokens();

        _collaterals = new IERC20[](1);
        _collaterals[0] = _pt;
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
        depositContracts[0] = address(0);
    }
}
