// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RenzoLibrary } from "./../../../../src/libraries/lrt/RenzoLibrary.sol";
import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";
import { EzEthHandler } from "./../../../../src/flash/lrt/EzEthHandler.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";
import { RENZO_RESTAKE_MANAGER, EZETH } from "../../../../src/Constants.sol";
import { IIonPool } from "./../../../../src/interfaces/IIonPool.sol";

import { IProviderLibraryExposed } from "../../../helpers/IProviderLibraryExposed.sol";
import { UniswapFlashswapDirectMintHandlerWithDust_Test } from
    "../handlers-base/UniswapFlashswapDirectMintHandlerWithDust.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RenzoLibraryExposed is IProviderLibraryExposed {
    function getEthAmountInForLstAmountOut(uint256 lstAmount) external view returns (uint256 ethAmountIn) {
        (ethAmountIn,) = RenzoLibrary.getEthAmountInForLstAmountOut(lstAmount);
    }

    function getLstAmountOutForEthAmountIn(uint256 ethAmount) external view returns (uint256 amountOut) {
        (amountOut,) = RenzoLibrary.getLstAmountOutForEthAmountIn(ethAmount);
    }
}

abstract contract EzEthHandler_ForkBase is LrtHandler_ForkBase {
    uint8 internal constant ilkIndex = 0;
    EzEthHandler ezEthHandler;
    IProviderLibraryExposed providerLibrary;

    function setUp() public virtual override {
        super.setUp();
        ezEthHandler = new EzEthHandler(ilkIndex, ionPool, gemJoins[ilkIndex], Whitelist(whitelist), WSTETH_WETH_POOL);

        EZETH.approve(address(ezEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < lens.ilkCount(IIonPool(address(ionPool))); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        providerLibrary = new RenzoLibraryExposed();

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        RenzoLibrary.depositForLrt(INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ilkIndex;
    }

    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return providerLibrary;
    }

    function _getHandler() internal view override returns (address) {
        return address(ezEthHandler);
    }
}

contract EzEthHandler_ForkTest is EzEthHandler_ForkBase, UniswapFlashswapDirectMintHandlerWithDust_Test {
    function setUp() public virtual override(EzEthHandler_ForkBase, LrtHandler_ForkBase) {
        super.setUp();
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = EZETH;
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](1);
        depositContracts[0] = address(RENZO_RESTAKE_MANAGER);
    }
}

contract EzEthHandlerWhitelist_ForkTest is EzEthHandler_ForkTest {
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
        _whitelist.approveProtocolWhitelist(address(ezEthHandler));

        ionPool.updateWhitelist(_whitelist);

        borrowerWhitelistProof = borrowerProofs[0];
    }
}

contract EzEthHandler_WithRateChange_ForkTest is EzEthHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ilkIndex, 3.5708923502395e27);
    }
}
