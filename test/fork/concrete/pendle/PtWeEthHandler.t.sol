// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WEETH_ADDRESS, PT_WEETH_POOL } from "../../../../src/Constants.sol";
import { PtHandler } from "../../../../src/flash/PtHandler.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";
import { IWeEth } from "../../../../src/interfaces/ProviderInterfaces.sol";
import { EtherFiLibrary } from "../../../../src/libraries/lrt/EtherFiLibrary.sol";
import { IIonPool } from "./../../../../src/interfaces/IIonPool.sol";

import { IProviderLibraryExposed } from "../../../helpers/IProviderLibraryExposed.sol";
import { PtHandler_ForkBase } from "../../../helpers/handlers/PtHandlerBase.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPPrincipalToken } from "pendle-core-v2-public/interfaces/IPPrincipalToken.sol";
import { IPMarketV3 } from "pendle-core-v2-public/interfaces/IPMarketV3.sol";

using EtherFiLibrary for IWeEth;

abstract contract PtWeEthHandler_ForkBase is PtHandler_ForkBase {
    uint8 internal constant ilkIndex = 0;
    PtHandler ptHandler;

    function setUp() public virtual override {
        super.setUp();
        ptHandler = new PtHandler({
            pool: ionPool,
            join: gemJoins[ilkIndex],
            whitelist: Whitelist(whitelist),
            _market: PT_WEETH_POOL
        });

        IERC20 _pt = ptHandler.PT();
        _pt.approve(address(ptHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < lens.ilkCount(IIonPool(address(ionPool))); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        deal(address(_pt), address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        deal(address(WEETH_ADDRESS), lender1, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender1);
        WEETH_ADDRESS.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, INITIAL_LENDER_UNDERLYING_BALANCE, emptyProof);
        vm.stopPrank();
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ilkIndex;
    }

    function _getHandler() internal view override returns (address) {
        return address(ptHandler);
    }

    // Not necessary
    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) { }

    function _getAmmPool() internal pure override returns (IPMarketV3) {
        return PT_WEETH_POOL;
    }

    function _getUnderlying() internal pure virtual override returns (address) {
        return address(WEETH_ADDRESS);
    }

    function _getTypedPtHandler() internal view override returns (PtHandler out) {
        address handler = _getHandler();
        assembly {
            out := handler
        }
    }
}

contract PtWeEthHandler_ForkTest is PtWeEthHandler_ForkBase {
    function _getCollaterals() internal view override returns (IERC20[] memory _collaterals) {
        (, IPPrincipalToken _PT,) = PT_WEETH_POOL.readTokens();

        _collaterals = new IERC20[](1);
        _collaterals[0] = _PT;
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
    }
}
