// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { WSTETH_ADDRESS, RSWETH, RSETH, WEETH_ADDRESS, EETH_ADDRESS } from "../../src/Constants.sol";
import { RswEthHandler } from "../../src/flash/lrt/RswEthHandler.sol";
import { LidoLibrary } from "../../src/libraries/lst/LidoLibrary.sol";
import { RestakedSwellLibrary } from "../../src/libraries/lrt/RestakedSwellLibrary.sol";
import { EtherFiLibrary } from "../../src/libraries/lrt/EtherFiLibrary.sol";
import { KelpDaoLibrary } from "../../src/libraries/lrt/KelpDaoLibrary.sol";
import { WeEthHandler } from "../../src/flash/lrt/WeEthHandler.sol";
import { RsEthHandler } from "../../src/flash/lrt/RsEthHandler.sol";
import { IWstEth, IWeEth, IRsEth, IRswEth } from "../../src/interfaces/ProviderInterfaces.sol";
import { Whitelist } from "../../src/Whitelist.sol";

import { Test } from "forge-std/Test.sol";

using LidoLibrary for IWstEth;
using RestakedSwellLibrary for IRswEth;
using EtherFiLibrary for IWeEth;
using KelpDaoLibrary for IRsEth;

contract TestFlashLeverage is Test {
    IonPool rswEthPool;
    RswEthHandler rswEthHandler;

    IonPool weEthPool;
    WeEthHandler weEthHandler;

    IonPool rsEthPool;
    RsEthHandler rsEthHandler;

    Whitelist whitelist;

    uint256 initialDeposit = 4 ether; // in collateral terms
    uint256 resultingAdditionalCollateral = 10 ether; // in collateral terms
    uint256 maxResultingDebt = 15 ether;

    function setUp() public {
        vm.pauseGasMetering();
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        weEthPool = IonPool(0x0000000000eaEbd95dAfcA37A39fd09745739b78);
        weEthHandler = WeEthHandler(payable(0xAB3c6236327FF77159B37f18EF85e8AC58034479));

        rswEthPool = IonPool(0x00000000007C8105548f9d0eE081987378a6bE93);
        rswEthHandler = RswEthHandler(payable(0x5039eEe75BA0cC3Ca41c654864303951798ff0D4));

        rsEthPool = IonPool(0x0000000000E33e35EE6052fae87bfcFac61b1da9);
        rsEthHandler = RsEthHandler(payable(0x335FBFf118829Aa5ef0ac91196C164538A21a45A));

        whitelist = Whitelist(0x7E317f99aA313669AaCDd8dB3927ff3aCB562dAD);

        vm.startPrank(whitelist.owner());
        whitelist.updateBorrowersRoot(0, bytes32(0));
        whitelist.updateLendersRoot(bytes32(0));
        vm.stopPrank();

        _setupPool(weEthPool);
        _setupPool(rswEthPool);
        _setupPool(rsEthPool);
    }

    function testWeEthHandler() public {
        weEthPool.addOperator(address(weEthHandler));

        WEETH_ADDRESS.approve(address(weEthHandler), type(uint256).max);
        EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
        WEETH_ADDRESS.depositForLrt(initialDeposit * 2);

        vm.resumeGasMetering();
        weEthHandler.flashswapAndMint(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp + 1_000_000_000_000,
            new bytes32[](0)
        );
    }

    function testRswEthHandler() public {
        rswEthPool.addOperator(address(rswEthHandler));

        RSWETH.approve(address(rswEthHandler), type(uint256).max);
        RSWETH.depositForLrt(initialDeposit * 2);

        vm.resumeGasMetering();
        rswEthHandler.flashswapAndMint(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp + 1_000_000_000_000,
            new bytes32[](0)
        );
    }

    function testRsEthHandler() public {
        rsEthPool.addOperator(address(rsEthHandler));

        RSETH.approve(address(rsEthHandler), type(uint256).max);
        EETH_ADDRESS.approve(address(RSETH), type(uint256).max);
        RSETH.depositForLrt(initialDeposit * 2);

        vm.resumeGasMetering();
        rsEthHandler.flashswapAndMint(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp + 1_000_000_000_000,
            new bytes32[](0)
        );
    }

    function _setupPool(IonPool pool) internal {
        vm.prank(pool.owner());
        pool.updateSupplyCap(1_000_000 ether);
        vm.prank(pool.owner());
        pool.updateIlkDebtCeiling(0, 1_000_000e45);
        WSTETH_ADDRESS.depositForLst(500 ether);
        WSTETH_ADDRESS.approve(address(pool), type(uint256).max);
        pool.supply(address(this), WSTETH_ADDRESS.balanceOf(address(this)), new bytes32[](0));
    }
}
