// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { BaseRsEthHandler } from "../../../../../src/flash/lrt/BaseRsEthHandler.sol";
import { Whitelist } from "../../../../../src/Whitelist.sol";
import { AerodromeFlashswapHandler } from "../../../../../src/flash/AerodromeFlashswapHandler.sol";
import { LrtHandler_ForkBase } from "../../../../helpers/handlers/LrtHandlerForkBase.sol";
import { IonHandler_ForkBase } from "../../../../helpers/handlers/IonHandlerForkBase.sol";
import {
    AerodromeFlashswapHandler_FuzzTest,
    AerodromeFlashswapHandler_WithRateChange_FuzzTest
} from "../../handlers-base/AerodromeFlashswapHandler.t.sol";
import { 
    BASE_RSETH_WETH_AERODROME,
    BASE_WETH,
    BASE_RSETH,
    BASE_RSETH_ETH_PRICE_CHAINLINK,
    RSETH_LRT_DEPOSIT_POOL
} from "../../../../../src/Constants.sol";
import { IProviderLibraryExposed } from "../../../../helpers/IProviderLibraryExposed.sol";

// import { IonHandler_ForkBase } from "../../../../helpers/handlers/IonHandlerForkBase.sol";
import { IonPoolSharedSetup } from "../../../../helpers/IonPoolSharedSetup.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

using SafeCast for int256;

contract RsEthWethHandler_ForkFuzzTest is AerodromeFlashswapHandler_FuzzTest {
    BaseRsEthHandler handler;
    uint8 immutable ILK_INDEX = 0;

    function setUp() public virtual override {
        super.setUp();
        handler = new BaseRsEthHandler(
            ILK_INDEX,
            ionPool,
            gemJoins[ILK_INDEX],
            Whitelist(whitelist),
            BASE_RSETH_WETH_AERODROME,
            BASE_WETH
        );

        BASE_RSETH.approve(address(handler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        deal(address(BASE_RSETH), address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getCollaterals() internal pure virtual override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = BASE_RSETH;
    }

    function _getHandler() internal view override returns (address) {
        return address(handler);
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ILK_INDEX;
    }

    function _getUnderlying() internal pure virtual override returns (address) {
        return address(BASE_WETH);
    }

    function _getInitialSpotPrice() internal view virtual override returns (uint256) {
        (, int256 ethPerRsEth,,,) = BASE_RSETH_ETH_PRICE_CHAINLINK.latestRoundData(); // [WAD]
        return ethPerRsEth.toUint256();
    }

    // NOTE Should be unused
    function _getProviderLibrary() internal pure override returns (IProviderLibraryExposed) {
        return IProviderLibraryExposed(address(0));
    }

    function _getDepositContracts() internal pure virtual override returns (address[] memory) {
        return new address[](1);
    }

    function _getForkRpc() internal view virtual override returns (string memory) {
        return vm.envString("BASE_MAINNET_RPC_URL");
    }
}

contract RsEthWethHandler_WithRateChange_ForkFuzzTest is
    RsEthWethHandler_ForkFuzzTest,
    AerodromeFlashswapHandler_WithRateChange_FuzzTest
{
    function setUp() public virtual override(LrtHandler_ForkBase, RsEthWethHandler_ForkFuzzTest) {
        RsEthWethHandler_ForkFuzzTest.setUp();
    }

    function _getCollaterals() internal pure override(IonPoolSharedSetup, RsEthWethHandler_ForkFuzzTest) returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = BASE_RSETH;
    }

    function _getDepositContracts() internal pure override(IonPoolSharedSetup, RsEthWethHandler_ForkFuzzTest) returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
        depositContracts[0] = address(RSETH_LRT_DEPOSIT_POOL);
    }

    function _getUnderlying() internal pure virtual override(LrtHandler_ForkBase, RsEthWethHandler_ForkFuzzTest) returns (address) {
        return address(BASE_WETH);
    }

    function _getInitialSpotPrice() internal view virtual override(LrtHandler_ForkBase, RsEthWethHandler_ForkFuzzTest) returns (uint256) {
        (, int256 ethPerRsEth,,,) = BASE_RSETH_ETH_PRICE_CHAINLINK.latestRoundData(); // [WAD]
        return ethPerRsEth.toUint256();
    }

    function _getForkRpc() internal view virtual override(IonHandler_ForkBase, RsEthWethHandler_ForkFuzzTest) returns (string memory) {
        return vm.envString("BASE_MAINNET_RPC_URL");
    }
}