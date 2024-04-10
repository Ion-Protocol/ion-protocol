// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { PtHandler } from "../../../../src/flash/PtHandler.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";
import { WadRayMath, RAY } from "../../../../src/libraries/math/WadRayMath.sol";

import { PtHandler_ForkBase } from "../../../helpers/handlers/PtHandlerBase.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

using WadRayMath for uint256;

abstract contract PtHandler_Test is PtHandler_ForkBase {
    function testFork_PtLeverage() public {
        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = 10e18;

        IERC20(_getUnderlying()).approve(_getHandler(), type(uint256).max);
        ionPool.addOperator(_getHandler());

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            _getTypedPtHandler().ptLeverage(
                initialDeposit, resultingAdditionalCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
            );
        }

        _getTypedPtHandler().ptLeverage(
            initialDeposit, resultingAdditionalCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;
        if (currentRate % RAY != 0) ++roundingError;

        uint256 currentDebt = ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(currentRate);
        assertLe(currentDebt, maxResultingDebt + roundingError);
        assertEq(_getCollaterals()[_getIlkIndex()].balanceOf(_getHandler()), 0);
        assertLe(IERC20(_getUnderlying()).balanceOf(_getHandler()), roundingError);
        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingAdditionalCollateral);
    }
}
