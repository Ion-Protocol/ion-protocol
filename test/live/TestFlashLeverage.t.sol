// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { WSTETH_ADDRESS, WEETH_ADDRESS, EETH_ADDRESS } from "../../src/Constants.sol";
import { LidoLibrary } from "../../src/libraries/lst/LidoLibrary.sol";
import { EtherFiLibrary } from "../../src/libraries/lrt/EtherFiLibrary.sol";
import { WeEthHandler } from "../../src/flash/lrt/WeEthHandler.sol";
import { IWstEth, IWeEth } from "../../src/interfaces/ProviderInterfaces.sol";
import { Whitelist } from "../../src/Whitelist.sol";

import { Test } from "forge-std/Test.sol";

using LidoLibrary for IWstEth;
using EtherFiLibrary for IWeEth;

contract TestFlashLeverage is Test {
    IonPool pool;
    WeEthHandler weEthHandler;
    Whitelist whitelist;

    uint256 initialDeposit = 4 ether; // in collateral terms
    uint256 resultingAdditionalCollateral = 10 ether; // in collateral terms
    uint256 maxResultingDebt = 15 ether;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        pool = IonPool(0x0000000000eaEbd95dAfcA37A39fd09745739b78);
        weEthHandler = WeEthHandler(payable(0xAB3c6236327FF77159B37f18EF85e8AC58034479));
        whitelist = Whitelist(0x7E317f99aA313669AaCDd8dB3927ff3aCB562dAD);

        vm.startPrank(whitelist.owner());
        whitelist.updateBorrowersRoot(0, bytes32(0));
        whitelist.updateLendersRoot(bytes32(0));
        vm.stopPrank();

        vm.prank(pool.owner());
        pool.updateSupplyCap(1_000_000 ether);
        WSTETH_ADDRESS.depositForLst(500 ether);
        WSTETH_ADDRESS.approve(address(pool), type(uint256).max);
        pool.supply(address(this), WSTETH_ADDRESS.balanceOf(address(this)), new bytes32[](0));
    }

    function testWeEthHandler() public {
        pool.addOperator(address(weEthHandler));

        WEETH_ADDRESS.approve(address(weEthHandler), type(uint256).max);
        EETH_ADDRESS.approve(address(WEETH_ADDRESS), type(uint256).max);
        WEETH_ADDRESS.depositForLrt(initialDeposit * 2);

        weEthHandler.flashswapAndMint(
            initialDeposit,
            resultingAdditionalCollateral,
            maxResultingDebt,
            block.timestamp + 1_000_000_000_000,
            new bytes32[](0)
        );
    }
}
