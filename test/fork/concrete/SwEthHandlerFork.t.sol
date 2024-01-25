// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ISwEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { SwEthHandler } from "../../../src/flash/handlers/SwEthHandler.sol";
import { SwellLibrary } from "../../../src/libraries/SwellLibrary.sol";
import { Whitelist } from "../../../src/Whitelist.sol";

import { IonHandler_ForkBase } from "../../helpers/IonHandlerForkBase.sol";
import { IProviderLibraryExposed } from "../../helpers/IProviderLibraryExposed.sol";
import { BalancerFlashloanDirectMintHandler_Test } from "./handlers-base/BalancerFlashloanDirectMintHandler.t.sol";
import { UniswapFlashswapHandler_Test } from "./handlers-base/UniswapFlashswapHandler.t.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

using SwellLibrary for ISwEth;

contract SwellLibraryExposed is IProviderLibraryExposed {
    ISwEth swEth;

    constructor(ISwEth swEth_) {
        swEth = swEth_;
    }

    function getEthAmountInForLstAmountOut(uint256 lstAmount) external view returns (uint256) {
        return swEth.getEthAmountInForLstAmountOut(lstAmount);
    }

    function getLstAmountOutForEthAmountIn(uint256 ethAmount) external view returns (uint256) {
        return swEth.getLstAmountOutForEthAmountIn(ethAmount);
    }
}

contract SwEthHandler_ForkBase is IonHandler_ForkBase {
    uint8 internal constant ilkIndex = 2;
    SwEthHandler swEthHandler;
    SwellLibraryExposed providerLibrary;

    function setUp() public virtual override {
        super.setUp();
        swEthHandler = new SwEthHandler(ilkIndex, ionPool, gemJoins[ilkIndex], Whitelist(whitelist), SWETH_ETH_POOL);

        IERC20(address(MAINNET_SWELL)).approve(address(swEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        providerLibrary = new SwellLibraryExposed(MAINNET_SWELL);

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        MAINNET_SWELL.depositForLst(INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ilkIndex;
    }

    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return providerLibrary;
    }

    function _getHandler() internal view override returns (address) {
        return address(swEthHandler);
    }
}

contract SwEthHandler_ForkTest is
    SwEthHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_Test,
    UniswapFlashswapHandler_Test
{
    function setUp() public virtual override(IonHandler_ForkBase, SwEthHandler_ForkBase) {
        super.setUp();

        // If price of the pool ends up being larger than the exchange rate,
        // then a direct 1:1 contract mint is more favorable
        uint256 exchangeRate = MAINNET_SWELL.ethToSwETHRate();
        sqrtPriceLimitX96 = uint160(Math.sqrt(uint256(exchangeRate << 192) / 1e18));
    }
}

contract SwEthHandlerWhitelist_ForkTest is SwEthHandler_ForkTest {
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
        _whitelist.approveProtocolWhitelist(address(swEthHandler));

        ionPool.updateWhitelist(_whitelist);

        borrowerWhitelistProof = borrowerProofs[0];
    }
}

contract SwEthHandler_WithRateChange_ForkTest is SwEthHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ilkIndex, 3.5708923502395e27);
    }
}
