// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPoolExposed } from "../../helpers/IonPoolSharedSetup.sol";
// import { IonHandler } from "../../../src/periphery/IonHandler.sol";
import { ERC20PresetMinterPauser } from "../../helpers/ERC20PresetMinterPauser.sol";
import { IHevm } from "../../helpers/echidna/IHevm.sol";
import { RoundedMath } from "../../../src/math/RoundedMath.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

IHevm constant hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

using RoundedMath for uint256;

abstract contract Handler is CommonBase, StdCheats, StdUtils {
    IonPoolExposed internal immutable ionPool;
    ERC20PresetMinterPauser internal immutable underlying;

    constructor(IonPoolExposed _ionPool, ERC20PresetMinterPauser _underlying) {
        ionPool = _ionPool;
        underlying = _underlying;
    }
}

contract LenderHandler is Handler {
    uint256 public totalHoldingsNormalized;

    constructor(IonPoolExposed _ionPool, ERC20PresetMinterPauser _underlying) Handler(_ionPool, _underlying) {
        underlying.approve(address(ionPool), type(uint256).max);
    }

    function supply(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);
        uint256 amountNormalized = amount.roundedRayDiv(ionPool.supplyFactor());

        if (amountNormalized == 0) return;
        totalHoldingsNormalized += amountNormalized;

        underlying.mint(address(this), amount);
        ionPool.supply(address(this), amount);
    }

    function withdraw(uint256 amount) public {
        // To prevent reverts, limit withdraw amounts to the available liquidity in the pool
        uint256 balance = Math.min(underlying.balanceOf(address(ionPool)), ionPool.balanceOf(address(this)));
        amount = bound(amount, 0, balance);

        uint256 amountNormalized = amount.roundedRayDiv(ionPool.supplyFactor());
        if (amountNormalized == 0) return;

        totalHoldingsNormalized -= amountNormalized;

        ionPool.withdraw(address(this), amount);
    }
}

contract BorrowerHandler is Handler {
    // IonHandler internal immutable ionHandler;

    constructor(
        IonPoolExposed _ionPool,
        // IonHandler _ionHandler,
        ERC20PresetMinterPauser _underlying
    )
        Handler(_ionPool, _underlying)
    {
        // underlying.approve(address(ionPool), type(uint256).max);
        // ionPool.hope(address(_ionHandler));
        // ionHandler = _ionHandler;
    }

    // function borrow(uint8 ilkIndex, uint256 amount) public {
    //     uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));
    //     ionHandler.borrow(_ilkIndex, amount);
    // }

    // function repay(address borrower, uint8 ilkIndex, uint256 amount) public {
    //     uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));
    //     ionHandler.repay(_ilkIndex, amount);
    // }

    // function modifyPosition(
    //     address borrower,
    //     uint8 ilkIndex,
    //     address collateralSource,
    //     address debtDestination,
    //     int256 changeInCollateral,
    //     int256 changeInNormalizedDebt
    // )
    //     public
    // { }

    // function gemJoin(address borrower, uint8 ilkIndex, uint256 amount) public {
    //     hevm.prank(borrower);
    //     underlying.approve(address(ionPool), type(uint256).max);
    //     hevm.prank(borrower);
    //     ionPool.gemJoin(ilkIndex, amount);
    // }
}

contract LiquidatorHandler is Handler {
    constructor(IonPoolExposed _ionPool, ERC20PresetMinterPauser _underlying) Handler(_ionPool, _underlying) { }
}
