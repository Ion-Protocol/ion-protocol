// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { ERC20PresetMinterPauser } from "./ERC20PresetMinterPauser.sol";

abstract contract BaseTestSetup is Test {
    ERC20PresetMinterPauser underlying;
    address internal TREASURY = vm.addr(2);
    uint8 internal constant DECIMALS = 18;
    string internal constant SYMBOL = "iWETH";
    string internal constant NAME = "Ion Wrapped Ether";

    function setUp() public virtual {
        underlying = new ERC20PresetMinterPauser("WETH", "Wrapped Ether");
    }
}
