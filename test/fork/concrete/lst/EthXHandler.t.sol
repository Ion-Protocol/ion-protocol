// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IStaderStakePoolsManager } from "../../../../src/interfaces/ProviderInterfaces.sol";
import { EthXHandler } from "../../../../src/flash/lst/EthXHandler.sol";
import { StaderLibrary } from "../../../../src/libraries/lst/StaderLibrary.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";

import { BalancerFlashloanDirectMintHandler_Test } from "../handlers-base/BalancerFlashloanDirectMintHandler.t.sol";
import { UniswapFlashloanBalancerSwapHandler_Test } from "../handlers-base/UniswapFlashloanBalancerSwapHandler.t.sol";
import { LstHandler_ForkBase } from "../../../helpers/handlers/LstHandlerForkBase.sol";
import { IProviderLibraryExposed } from "../../../helpers/IProviderLibraryExposed.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

using StaderLibrary for IStaderStakePoolsManager;

contract StaderLibraryExposed is IProviderLibraryExposed {
    IStaderStakePoolsManager staderDeposit;

    constructor(IStaderStakePoolsManager staderDeposit_) {
        staderDeposit = staderDeposit_;
    }

    function getEthAmountInForLstAmountOut(uint256 lstAmount) external view returns (uint256) {
        return staderDeposit.getEthAmountInForLstAmountOut(lstAmount);
    }

    function getLstAmountOutForEthAmountIn(uint256 ethAmount) external view returns (uint256) {
        return staderDeposit.getLstAmountOutForEthAmountIn(ethAmount);
    }
}

abstract contract EthXHandler_ForkBase is LstHandler_ForkBase {
    uint8 internal constant ilkIndex = 1;
    EthXHandler ethXHandler;
    StaderLibraryExposed staderLibraryExposed;

    function setUp() public virtual override {
        // Since Balancer EthX pool has no liquidity, this needs to be pinned to
        // a specific block
        forkBlock = 18_537_430;
        super.setUp();
        ethXHandler = new EthXHandler(
            ilkIndex,
            ionPool,
            gemJoins[ilkIndex],
            MAINNET_STADER,
            Whitelist(whitelist),
            WSTETH_WETH_POOL,
            ETHX_WETH_POOL,
            0x37b18b10ce5635a84834b26095a0ae5639dcb7520000000000000000000005cb
        );

        staderLibraryExposed = new StaderLibraryExposed(MAINNET_STADER);

        IERC20(address(MAINNET_ETHX)).approve(address(ethXHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        MAINNET_STADER.depositForLst(INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ilkIndex;
    }

    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return staderLibraryExposed;
    }

    function _getHandler() internal view override returns (address) {
        return address(ethXHandler);
    }
}

contract EthXHandler_ForkTest is
    EthXHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_Test,
    UniswapFlashloanBalancerSwapHandler_Test
{
    function setUp() public virtual override(EthXHandler_ForkBase, LstHandler_ForkBase) {
        super.setUp();
    }
}

contract EthXHandlerWhitelist_ForkTest is EthXHandler_ForkTest {
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
        _whitelist.approveProtocolWhitelist(address(ethXHandler));

        ionPool.updateWhitelist(_whitelist);

        borrowerWhitelistProof = borrowerProofs[0];
    }
}

contract EthXHandler_WithRateChange_ForkTest is EthXHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ilkIndex, 3.5708923502395e27);
    }
}
