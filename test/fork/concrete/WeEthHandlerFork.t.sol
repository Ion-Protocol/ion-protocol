// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWeEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { EtherFiLibrary } from "../../../src/libraries/EtherFiLibrary.sol";
import { WeEthIonHandler_ForkBase } from "../../helpers/weETH/WeEthIonHandlerForkBase.sol";
import { WeEthHandler } from "../../../src/flash/handlers/WeEthHandler.sol";
import { Whitelist } from "../../../src/Whitelist.sol";
import { WEETH_ADDRESS, EETH_ADDRESS } from "../../../src/Constants.sol";

import { IProviderLibraryExposed } from "../../helpers/IProviderLibraryExposed.sol";
import { BalancerFlashloanDirectMintUniswapSwapHandler_Test } from
    "./handlers-base/BalancerFlashloanDirectMintUniswapSwapHandler.t.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

using EtherFiLibrary for IWeEth;

contract EtherFiLibraryExposed is IProviderLibraryExposed {
    IWeEth weEth;

    constructor(IWeEth weEth_) {
        weEth = weEth_;
    }

    function getEthAmountInForLstAmountOut(uint256 lstAmount) external view returns (uint256) {
        return weEth.getEthAmountInForLstAmountOut(lstAmount);
    }

    function getLstAmountOutForEthAmountIn(uint256 ethAmount) external view returns (uint256) {
        return weEth.getLstAmountOutForEthAmountIn(ethAmount);
    }
}

contract WeEthHandler_ForkBase is WeEthIonHandler_ForkBase {
    uint8 internal constant ilkIndex = 0;
    WeEthHandler weEthHandler;
    IProviderLibraryExposed providerLibrary;

    function setUp() public virtual override {
        console.log("b1");
        super.setUp();
        weEthHandler = new WeEthHandler(ilkIndex, ionPool, gemJoins[ilkIndex], Whitelist(whitelist), WSTETH_WETH_POOL);

        WEETH_ADDRESS.approve(address(weEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        providerLibrary = new EtherFiLibraryExposed(WEETH_ADDRESS);

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
        WEETH_ADDRESS.depositForLrt(INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ilkIndex;
    }

    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return providerLibrary;
    }

    function _getHandler() internal view override returns (address) {
        return address(weEthHandler);
    }
}

contract WeEthHandler_ForkTest is WeEthHandler_ForkBase, BalancerFlashloanDirectMintUniswapSwapHandler_Test {
    function setUp() public virtual override(WeEthHandler_ForkBase, WeEthIonHandler_ForkBase) {
        super.setUp();
    }
}
