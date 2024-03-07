// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IRsEth } from "../../../../src/interfaces/ProviderInterfaces.sol";
import { KelpDaoLibrary } from "../../../../src/libraries/lrt/KelpDaoLibrary.sol";
import { RsEthHandler } from "../../../../src/flash/lrt/RsEthHandler.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";
import { RSETH, RSETH_LRT_DEPOSIT_POOL } from "../../../../src/Constants.sol";
import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";

import { IProviderLibraryExposed } from "../../../helpers/IProviderLibraryExposed.sol";
import { UniswapFlashswapDirectMintHandler_Test } from "../handlers-base/UniswapFlashswapDirectMintHandler.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

using KelpDaoLibrary for IRsEth;

contract KelpDaoLibraryExposed is IProviderLibraryExposed {
    IRsEth rsEth;

    constructor(IRsEth rsEth_) {
        rsEth = rsEth_;
    }

    function getEthAmountInForLstAmountOut(uint256 lstAmount) external view returns (uint256) {
        return rsEth.getEthAmountInForLstAmountOut(lstAmount);
    }

    function getLstAmountOutForEthAmountIn(uint256 ethAmount) external view returns (uint256) {
        return rsEth.getLstAmountOutForEthAmountIn(ethAmount);
    }
}

abstract contract RsEthHandler_ForkBase is LrtHandler_ForkBase {
    uint8 internal constant ilkIndex = 0;
    RsEthHandler rsEthHandler;
    IProviderLibraryExposed providerLibrary;

    function setUp() public virtual override {
        super.setUp();
        rsEthHandler = new RsEthHandler(ilkIndex, ionPool, gemJoins[ilkIndex], Whitelist(whitelist), WSTETH_WETH_POOL);

        RSETH.approve(address(rsEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        providerLibrary = new KelpDaoLibraryExposed(RSETH);

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        RSETH.depositForLrt(INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ilkIndex;
    }

    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return providerLibrary;
    }

    function _getHandler() internal view override returns (address) {
        return address(rsEthHandler);
    }
}

contract RsEthHandler_ForkTest is RsEthHandler_ForkBase, UniswapFlashswapDirectMintHandler_Test {
    function setUp() public virtual override(RsEthHandler_ForkBase, LrtHandler_ForkBase) {
        super.setUp();
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = RSETH;
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
        depositContracts[0] = address(RSETH_LRT_DEPOSIT_POOL);
    }
}

contract RsEthHandlerWhitelist_ForkTest is RsEthHandler_ForkTest {
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

    function setUp() public virtual override {
        super.setUp();

        bytes32[] memory borrowerRoots = new bytes32[](1);
        borrowerRoots[0] = borrowerWhitelistRoot;

        _whitelist = new Whitelist(borrowerRoots, bytes32(0));
        _whitelist.updateBorrowersRoot(ilkIndex, borrowerWhitelistRoot);
        _whitelist.approveProtocolWhitelist(address(rsEthHandler));

        ionPool.updateWhitelist(_whitelist);

        borrowerWhitelistProof = borrowerProofs[0];
    }
}

contract RsEthHandler_WithRateChange_ForkTest is RsEthHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();
    }
}
