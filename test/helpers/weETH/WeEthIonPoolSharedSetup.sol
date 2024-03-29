// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPoolSharedSetup } from "../IonPoolSharedSetup.sol";
import { WEETH_ADDRESS, WSTETH_ADDRESS } from "../../../src/Constants.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract WeEthIonPoolSharedSetup is IonPoolSharedSetup {
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

        super.setUp();
    }

    function _getUnderlying() internal pure override returns (address) {
        return address(WSTETH_ADDRESS);
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
