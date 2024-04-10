// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandler_ForkBase } from "./IonHandlerForkBase.sol";
import { IonPoolSharedSetup } from "../IonPoolSharedSetup.sol";
import { PtHandler } from "../../../src/flash/PtHandler.sol";

import { IPMarketV3 } from "pendle-core-v2-public/interfaces/IPMarketV3.sol";
import { PendlePtOracleLib } from "pendle-core-v2-public/oracles/PendlePtOracleLib.sol";

abstract contract PtHandler_ForkBase is IonHandler_ForkBase {
    using PendlePtOracleLib for IPMarketV3;

    function setUp() public virtual override {
        for (uint256 i = 0; i < 2; i++) {
            config.minimumProfitMargins.pop();
            config.reserveFactors.pop();
            config.optimalUtilizationRates.pop();
            config.distributionFactors.pop();
            debtCeilings.pop();
            config.adjustedAboveKinkSlopes.pop();
            config.minimumAboveKinkSlopes.pop();
        }
        config.distributionFactors[0] = 1e4;

        if (forkBlock == 0) vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"));
        else vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"), forkBlock);
        IonPoolSharedSetup.setUp();

        _getAmmPool().increaseObservationsCardinalityNext(288);
        uint256 spot = _getAmmPool().getPtToSyRate(1 hours);

        spotOracles[0].setPrice(spot);

        vm.deal(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        vm.deal(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);
    }

    function _getAmmPool() internal virtual returns (IPMarketV3);

    function _getTypedPtHandler() internal view virtual returns (PtHandler out);
}
