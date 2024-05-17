// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ERC20PresetMinterPauser } from "./ERC20PresetMinterPauser.sol";
import { WETH_ADDRESS } from "../../src/Constants.sol";

import { Test } from "forge-std/Test.sol";
import { VmSafe as Vm } from "forge-std/Vm.sol";

abstract contract BaseTestSetup is Test {
    modifier prankAgnostic() {
        (Vm.CallerMode mode, address msgSender,) = vm.readCallers();
        if (mode == Vm.CallerMode.Prank || mode == Vm.CallerMode.RecurrentPrank) {
            vm.stopPrank();
        }

        _;

        if (mode == Vm.CallerMode.Prank) {
            vm.prank(msgSender);
        } else if (mode == Vm.CallerMode.RecurrentPrank) {
            vm.startPrank(msgSender);
        }
    }

    ERC20PresetMinterPauser underlying;
    address internal TREASURY = vm.addr(2);
    uint8 internal constant DECIMALS = 18;
    string internal constant SYMBOL = "iWETH";
    string internal constant NAME = "Ion Wrapped Ether";

    function setUp() public virtual {
        underlying = new ERC20PresetMinterPauser("WETH", "Wrapped Ether");
    }
}
