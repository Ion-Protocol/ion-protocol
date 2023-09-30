// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IonPool } from "../../../src/IonPool.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {IHevm} from "../../echidna/IHevm.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

IHevm constant hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

abstract contract Handler is CommonBase, StdCheats, StdUtils {
    IonPool internal immutable ionPool;
    ERC20PresetMinterPauser internal immutable underlying;

    constructor(IonPool _ionPool, ERC20PresetMinterPauser _underlying) {
        ionPool = _ionPool;
        underlying = _underlying;
    }
}

contract LenderHandler is Handler {
    constructor(IonPool _ionPool, ERC20PresetMinterPauser _underlying) Handler(_ionPool, _underlying) { }

    function supply(address lender, uint256 amount) public {
        hevm.prank(lender);
        underlying.approve(address(ionPool), type(uint256).max);
        hevm.prank(lender);
        ionPool.supply(lender, amount);
    }
    
    function withdraw(address lender, uint256 amount) public {
        hevm.prank(lender);
        ionPool.withdraw(lender, amount);
    }
}

contract BorrowerHandler is Handler {
    constructor(IonPool _ionPool, ERC20PresetMinterPauser _underlying) Handler(_ionPool, _underlying) { }

    function borrow(address borrower, uint8 ilkIndex, uint256 amount) public {
        hevm.prank(borrower);
        ionPool.borrow(ilkIndex, amount);
    }

    function repay(address borrower, uint8 ilkIndex, uint256 amount) public {
        hevm.prank(borrower);
        underlying.approve(address(ionPool), type(uint256).max);
        hevm.prank(borrower);
        ionPool.repay(ilkIndex, amount);
    }

    function modifyPosition(address borrower, uint8 ilkIndex, address collateralSource, address debtDestination, int256 changeInCollateral, int256 changeInNormalizedDebt) public {

    }

    function gemJoin(address borrower, uint8 ilkIndex, uint256 amount) public {
        hevm.prank(borrower);
        underlying.approve(address(ionPool), type(uint256).max);
        hevm.prank(borrower);
        ionPool.gemJoin(ilkIndex, amount);
    }

}

contract LiquidatorHandler is Handler {
    constructor(IonPool _ionPool, ERC20PresetMinterPauser _underlying) Handler(_ionPool, _underlying) { }
}
