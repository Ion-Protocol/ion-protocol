// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWeEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { EtherFiLibrary } from "../../../src/libraries/EtherFiLibrary.sol";
import { WeEthIonHandler_ForkBase } from "../../helpers/weETH/WeEthIonHandlerForkBase.sol";
import { WeEthHandler } from "../../../src/flash/handlers/WeEthHandler.sol";
import { Whitelist } from "../../../src/Whitelist.sol";
import { WEETH_ADDRESS, EETH_ADDRESS } from "../../../src/Constants.sol";

import { IProviderLibraryExposed } from "../../helpers/IProviderLibraryExposed.sol";
import { UniswapFlashswapDirectMintHandler_Test } from "./handlers-base/UniswapFlashswapDirectMintHandler.t.sol";

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

contract WeEthHandler_ForkTest is WeEthHandler_ForkBase, UniswapFlashswapDirectMintHandler_Test {
    function setUp() public virtual override(WeEthHandler_ForkBase, WeEthIonHandler_ForkBase) {
        super.setUp();
    }
}

contract WeEthHandlerWhitelist_ForkTest is WeEthHandler_ForkTest {
    // generate merkle root
    // ["0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496"],
    // ["0x2222222222222222222222222222222222222222"],
    // => 0xb51a382d5bcb4cd5fe50a7d4d8abaf056ac1a6961cf654ec4f53a570ab75a30b

    bytes32 borrowerWhitelistRoot = 0x846dfddafc70174f2089edda6408bf9dd643c19ee06ff11643b614f0e277d6e3;

    bytes32[][] borrowerProofs = [
        [bytes32(0x708e7cb9a75ffb24191120fba1c3001faa9078147150c6f2747569edbadee751)],
        [bytes32(0xa6e6806303186f9c20e1af933c7efa83d98470acf93a10fb8da8b1d9c2873640)]
    ];

    Whitelist _whitelist;

    function setUp() public override {
        super.setUp();

        bytes32[] memory borrowerRoots = new bytes32[](1);
        borrowerRoots[0] = borrowerWhitelistRoot;

        _whitelist = new Whitelist(borrowerRoots, bytes32(0));
        _whitelist.updateBorrowersRoot(ilkIndex, borrowerWhitelistRoot);
        _whitelist.approveProtocolWhitelist(address(weEthHandler));

        ionPool.updateWhitelist(_whitelist);

        borrowerWhitelistProof = borrowerProofs[0];
    }
}

contract WeEthHandler_WithRateChange_ForkTest is WeEthHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ilkIndex, 3.5708923502395e27);
    }
}
