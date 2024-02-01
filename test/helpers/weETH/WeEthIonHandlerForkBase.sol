// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandler_ForkBase } from "../IonHandlerForkBase.sol";
import {
    WEETH_ADDRESS,
    EETH_ADDRESS,
    WSTETH_ADDRESS,
    REDSTONE_WEETH_ETH_PRICE_FEED,
    WSTETH_ADDRESS
} from "../../../src/Constants.sol";
import { IonPoolSharedSetup } from "../IonPoolSharedSetup.sol";
import { WadRayMath } from "../../../src/libraries/math/WadRayMath.sol";
import { LidoLibrary } from "../../../src/libraries/LidoLibrary.sol";
import { IWstEth } from "../../../src/interfaces/ProviderInterfaces.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

using LidoLibrary for IWstEth;
using WadRayMath for uint256;

abstract contract WeEthIonHandler_ForkBase is IonHandler_ForkBase {
    function setUp() public virtual override {
        console.log("c1");
        for (uint256 i = 0; i < 2; i++) {
            minimumProfitMargins.pop();
            adjustedReserveFactors.pop();
            optimalUtilizationRates.pop();
            distributionFactors.pop();
            debtCeilings.pop();
            adjustedAboveKinkSlopes.pop();
            minimumAboveKinkSlopes.pop();
        }
        distributionFactors[0] = 1e4;
        console.log("c2");

        if (forkBlock == 0) vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"));
        else vm.createSelectFork(vm.envString("MAINNET_ARCHIVE_RPC_URL"), forkBlock);
        IonPoolSharedSetup.setUp();

        (, int256 stEthSpot,,,) = STETH_ETH_CHAINLINK.latestRoundData();
        uint256 wstEthInEthSpot = MAINNET_WSTETH.getStETHByWstETH(uint256(stEthSpot));

        // ETH / weETH [8 decimals]
        (, int256 answer,,,) = REDSTONE_WEETH_ETH_PRICE_FEED.latestRoundData();

        // wstETH / weETH [18 decimals]
        uint256 weEthWstEthSpot = uint256(answer).scaleUpToWad(8).wadMulDown(wstEthInEthSpot);

        spotOracles[0].setPrice(weEthWstEthSpot);

        vm.deal(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        vm.deal(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender1);
        uint256 amount = WSTETH_ADDRESS.depositForLst(INITIAL_LENDER_UNDERLYING_BALANCE);
        WSTETH_ADDRESS.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, amount, emptyProof);
        vm.stopPrank();

        // vm.startPrank(lender2);
        // EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
        // amount = WEETH_ADDRESS.depositForLrt(INITIAL_LENDER_UNDERLYING_BALANCE);
        // WEETH_ADDRESS.approve(address(ionPool), type(uint256).max);
        // ionPool.supply(lender2, amount, emptyProof);
        // vm.stopPrank();
    }

    function _getUnderlying() internal pure override returns (address) {
        return address(WSTETH_ADDRESS);
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = WEETH_ADDRESS;
    }
}
