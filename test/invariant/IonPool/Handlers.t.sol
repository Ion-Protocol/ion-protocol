// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { IonRegistry } from "src/periphery/IonRegistry.sol";
import { GemJoin } from "src/join/GemJoin.sol";

import { IonPoolExposed } from "test/helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";
import { IHevm } from "test/helpers/echidna/IHevm.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

// TODO: Clean up HEVM to be in one spot
IHevm constant hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

using RoundedMath for uint256;

abstract contract Handler is CommonBase, StdCheats, StdUtils {
    IonPoolExposed internal immutable ionPool;
    ERC20PresetMinterPauser internal immutable underlying;
    bool immutable LOG;

    constructor(IonPoolExposed _ionPool, ERC20PresetMinterPauser _underlying, bool _log) {
        ionPool = _ionPool;
        underlying = _underlying;
        LOG = _log;
    }
}

contract LenderHandler is Handler {
    uint256 public totalHoldingsNormalized;

    constructor(
        IonPoolExposed _ionPool,
        ERC20PresetMinterPauser _underlying,
        bool _log
    )
        Handler(_ionPool, _underlying, _log)
    {
        underlying.approve(address(ionPool), type(uint256).max);
    }

    function supply(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);
        uint256 amountNormalized = amount.rayDivDown(ionPool.supplyFactor());

        if (amountNormalized == 0) return;
        totalHoldingsNormalized += amountNormalized;

        if (LOG) console.log("supply", amount);

        underlying.mint(address(this), amount);
        ionPool.supply(address(this), amount, new bytes32[](0));
    }

    function withdraw(uint256 amount) public {
        // To prevent reverts, limit withdraw amounts to the available liquidity in the pool
        uint256 balance = Math.min(ionPool.weth(), ionPool.balanceOf(address(this)));
        amount = bound(amount, 0, balance);

        uint256 amountNormalized = amount.rayDivUp(ionPool.supplyFactor());
        if (amountNormalized == 0) return;

        totalHoldingsNormalized -= amountNormalized;

        if (LOG) console.log("withdraw", amount);

        ionPool.withdraw(address(this), amount);
    }
}

contract BorrowerHandler is Handler {
    IonRegistry immutable registry;
    ERC20PresetMinterPauser[] collaterals;

    constructor(
        IonPoolExposed _ionPool,
        IonRegistry _registry,
        ERC20PresetMinterPauser _underlying,
        ERC20PresetMinterPauser[] memory _collaterals,
        bool _log
    )
        Handler(_ionPool, _underlying, _log)
    {
        underlying.approve(address(_ionPool), type(uint256).max);
        ionPool.addOperator(address(_ionPool));
        registry = _registry;
        collaterals = _collaterals;
    }

    function borrow(uint8 ilkIndex, uint256 normalizedAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        uint256 ilkRate = ionPool.rate(_ilkIndex);
        uint256 maxAdditionalNormalizedDebt;
        {
            uint256 vaultCollateral = ionPool.collateral(_ilkIndex, address(this));
            uint256 ilkSpot = ionPool.spot(_ilkIndex).getSpot();
            uint256 vaultNormalizedDebt = ionPool.normalizedDebt(_ilkIndex, address(this));

            uint256 currentDebt = vaultNormalizedDebt.rayMulDown(ilkRate);
            uint256 debtLimit = ilkSpot.rayMulDown(vaultCollateral);
            uint256 maxAdditionalDebt = debtLimit - currentDebt;
            maxAdditionalNormalizedDebt = _min(maxAdditionalDebt.rayDivDown(ilkRate), type(uint64).max);
        }

        uint256 poolLiquidity = ionPool.weth();
        uint256 normalizedPoolLiquidity = poolLiquidity.rayDivDown(ilkRate);

        normalizedAmount = _min(bound(normalizedAmount, 0, maxAdditionalNormalizedDebt), normalizedPoolLiquidity);

        if (LOG) console.log("borrow", normalizedAmount);

        ionPool.borrow(_ilkIndex, address(this), address(this), normalizedAmount, new bytes32[](0));
    }

    function repay(uint8 ilkIndex, uint256 normalizedAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        uint256 currentNormalizedDebt = ionPool.normalizedDebt(_ilkIndex, address(this));
        normalizedAmount = bound(normalizedAmount, 0, currentNormalizedDebt);

        if (LOG) console.log("repay", normalizedAmount);

        ionPool.repay(_ilkIndex, address(this), address(this), normalizedAmount);
    }

    function depositCollateral(uint8 ilkIndex, uint256 amount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        amount = bound(amount, 0, ionPool.gem(_ilkIndex, address(this)));

        if (LOG) console.log("depositCollateral", amount);

        ionPool.depositCollateral(_ilkIndex, address(this), address(this), amount, new bytes32[](0));
    }

    function withdrawCollateral(uint8 ilkIndex, uint256 amount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        uint256 ilkRate = ionPool.rate(_ilkIndex);
        uint256 maxRemovableCollateral;
        {
            uint256 vaultCollateral = ionPool.collateral(_ilkIndex, address(this));
            uint256 ilkSpot = ionPool.spot(_ilkIndex).getSpot();
            uint256 vaultNormalizedDebt = ionPool.normalizedDebt(_ilkIndex, address(this));

            uint256 currentDebt = vaultNormalizedDebt.rayMulDown(ilkRate);
            uint256 minimumCollateral = currentDebt.rayDivUp(ilkSpot);
            maxRemovableCollateral = vaultCollateral - minimumCollateral;
        }

        amount = bound(amount, 0, maxRemovableCollateral);

        if (LOG) console.log("withdrawCollateral", amount);

        ionPool.withdrawCollateral(ilkIndex, address(this), address(this), amount);
    }

    function gemJoin(uint8 ilkIndex, uint256 amount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        GemJoin _gemJoin = registry.gemJoins(_ilkIndex);
        ERC20PresetMinterPauser gem = collaterals[_ilkIndex];
        gem.approve(address(_gemJoin), amount);
        gem.mint(address(this), amount);

        amount = bound(amount, 0, gem.balanceOf(address(this)));

        if (LOG) console.log("gemJoin", amount);

        _gemJoin.join(address(this), amount);
    }

    function gemExit(uint8 ilkIndex, uint256 amount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        amount = bound(amount, 0, ionPool.gem(_ilkIndex, address(this)));
        GemJoin _gemJoin = registry.gemJoins(_ilkIndex);

        if (LOG) console.log("gemExit", amount);

        _gemJoin.exit(address(this), amount);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract LiquidatorHandler is Handler {
    constructor(
        IonPoolExposed _ionPool,
        ERC20PresetMinterPauser _underlying,
        bool _log
    )
        Handler(_ionPool, _underlying, _log)
    { }
}
