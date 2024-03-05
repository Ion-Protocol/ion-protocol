// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonHandler_ForkBase } from "./IonHandlerForkBase.sol";
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

abstract contract LrtHandler_ForkBase is IonHandler_ForkBase {
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

        (, int256 stEthSpot,,,) = STETH_ETH_CHAINLINK.latestRoundData();
        uint256 wstEthInEthSpot = MAINNET_WSTETH.getStETHByWstETH(uint256(stEthSpot));

        // ETH / weETH [8 decimals]
        (, int256 answer,,,) = REDSTONE_WEETH_ETH_PRICE_FEED.latestRoundData();

        // wstETH / weETH [18 decimals]
        uint256 weEthWstEthSpot = uint256(answer).scaleUpToWad(8).wadDivDown(wstEthInEthSpot);

        spotOracles[0].setPrice(weEthWstEthSpot);

        vm.deal(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        vm.deal(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender1);
        uint256 amount = WSTETH_ADDRESS.depositForLst(INITIAL_LENDER_UNDERLYING_BALANCE);
        WSTETH_ADDRESS.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, amount, emptyProof);
        vm.stopPrank();
    }

    function _getUnderlying() internal pure override returns (address) {
        return address(WSTETH_ADDRESS);
    }
}
