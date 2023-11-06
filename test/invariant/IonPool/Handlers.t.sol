// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RoundedMath, WAD, RAY, RAD } from "src/libraries/math/RoundedMath.sol";
import { IonRegistry } from "src/periphery/IonRegistry.sol";
import { GemJoin } from "src/join/GemJoin.sol";

import { IonPoolExposed } from "test/helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";
import { IHevm } from "test/helpers/echidna/IHevm.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

// TODO: Clean up HEVM to be in one spot
IHevm constant hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

using RoundedMath for uint256;
using Strings for uint256;
using Strings for uint8;

library DecimalToFixedPoint {
    function toFixedPointString(uint256 value, uint256 scale) internal pure returns (string memory) {
        return string.concat(
            value / scale == 0 ? "0" : (value / scale).toString(),
            ".",
            value % scale == 0 ? "0" : (value % scale).toString()
        );
    }
}

enum Actions {
    SUPPLY,
    WITHDRAW,
    BORROW,
    REPAY,
    DEPOSIT_COLLATERAL,
    WITHDRAW_COLLATERAL,
    GEM_JOIN,
    GEM_EXIT
}

abstract contract Handler is CommonBase, StdCheats, StdUtils {
    using DecimalToFixedPoint for uint256;

    IonPoolExposed internal immutable ionPool;
    ERC20PresetMinterPauser internal immutable underlying;
    IonRegistry internal immutable registry;

    bool immutable LOG;
    bool immutable REPORT;
    string internal constant REPORT_FILE = "report.csv";

    function _warpTime(uint256 warpTimeAmount) internal {
        warpTimeAmount = bound(warpTimeAmount, 100, 10_000);
        hevm.warp(block.timestamp + warpTimeAmount);
    }

    constructor(
        IonPoolExposed _ionPool,
        ERC20PresetMinterPauser _underlying,
        IonRegistry _registry,
        bool _log,
        bool _report
    ) {
        ionPool = _ionPool;
        underlying = _underlying;
        registry = _registry;
        LOG = _log;
        REPORT = _report;
    }

    struct GlobalPoolState {
        uint256 supplyFactor;
        uint256 totalSupply;
        uint256 totalDebt;
        uint256 wethLiquidity;
    }

    struct IlkIndexedPoolState {
        uint256 totalNormalizedDebt;
        uint256 rate;
        uint256 totalGem;
    }

    function reportAction(Actions actions, uint8 ilkIndex, uint256 amount) internal {
        vm.writeLine(REPORT_FILE, "Action, IlkIndex, Amount");

        if (actions == Actions.SUPPLY) {
            vm.writeLine(REPORT_FILE, string.concat("SUPPLY, ", "-, ", amount.toFixedPointString(WAD)));
        } else if (actions == Actions.WITHDRAW) {
            vm.writeLine(REPORT_FILE, string.concat("WITHDRAW, ", "-, ", amount.toFixedPointString(WAD)));
        } else if (actions == Actions.BORROW) {
            vm.writeLine(
                REPORT_FILE, string.concat("BORROW, ", ilkIndex.toString(), ", ", amount.toFixedPointString(WAD))
            );
        } else if (actions == Actions.REPAY) {
            vm.writeLine(
                REPORT_FILE, string.concat("REPAY, ", ilkIndex.toString(), ", ", amount.toFixedPointString(WAD))
            );
        } else if (actions == Actions.DEPOSIT_COLLATERAL) {
            vm.writeLine(
                REPORT_FILE,
                string.concat("DEPOSIT_COLLATERAL, ", ilkIndex.toString(), ", ", amount.toFixedPointString(WAD))
            );
        } else if (actions == Actions.WITHDRAW_COLLATERAL) {
            vm.writeLine(
                REPORT_FILE,
                string.concat("WITHDRAW_COLLATERAL, ", ilkIndex.toString(), ", ", amount.toFixedPointString(WAD))
            );
        } else if (actions == Actions.GEM_JOIN) {
            vm.writeLine(
                REPORT_FILE, string.concat("GEM_JOIN, ", ilkIndex.toString(), ", ", amount.toFixedPointString(WAD))
            );
        } else if (actions == Actions.GEM_EXIT) {
            vm.writeLine(
                REPORT_FILE, string.concat("GEM_EXIT, ", ilkIndex.toString(), ", ", amount.toFixedPointString(WAD))
            );
        }

        GlobalPoolState memory globalState;
        IlkIndexedPoolState[3] memory ilkIndexedState;

        globalState.supplyFactor = ionPool.supplyFactor();
        globalState.totalSupply = ionPool.totalSupply();
        globalState.totalDebt = ionPool.debt();
        globalState.wethLiquidity = ionPool.weth();

        require(ilkIndexedState.length == ionPool.ilkCount(), "invariant/IonPool/Handlers.t.sol: Ilk count mismatch");
        for (uint256 i = 0; i < ilkIndexedState.length; ++i) {
            uint8 _ilkIndex = uint8(i);
            ilkIndexedState[i].totalNormalizedDebt = ionPool.totalNormalizedDebt(_ilkIndex);
            ilkIndexedState[i].rate = ionPool.rate(_ilkIndex);
            ilkIndexedState[i].totalGem = registry.gemJoins(_ilkIndex).totalGem();
        }

        vm.writeLine(REPORT_FILE, "");
        vm.writeLine(REPORT_FILE, "GLOBAL STATE CHANGES");
        vm.writeLine(REPORT_FILE, "Supply Factor, Total Supply, Total Debt, WETH Liquidity");
        vm.writeLine(
            REPORT_FILE,
            string.concat(
                globalState.supplyFactor.toString(),
                ", ",
                globalState.totalSupply.toFixedPointString(WAD),
                ", ",
                globalState.totalDebt.toFixedPointString(RAD),
                ", ",
                globalState.wethLiquidity.toFixedPointString(WAD)
            )
        );

        vm.writeLine(REPORT_FILE, "");
        vm.writeLine(REPORT_FILE, "ILK STATE CHANGES");
        for (uint256 i = 0; i < ilkIndexedState.length; ++i) {
            vm.writeLine(REPORT_FILE, string.concat("ILK", i.toString()));
            vm.writeLine(REPORT_FILE, "Total Normalized Debt, Total Gem, Rate");
            vm.writeLine(
                REPORT_FILE,
                string.concat(
                    ilkIndexedState[i].totalNormalizedDebt.toFixedPointString(WAD),
                    ", ",
                    ilkIndexedState[i].totalGem.toFixedPointString(WAD),
                    ", ",
                    ilkIndexedState[i].rate.toFixedPointString(RAY)
                )
            );
            vm.writeLine(REPORT_FILE, "");
        }

        vm.writeLine(REPORT_FILE, "");
    }
}

contract LenderHandler is Handler {
    uint256 public totalHoldingsNormalized;

    constructor(
        IonPoolExposed _ionPool,
        IonRegistry _registry,
        ERC20PresetMinterPauser _underlying,
        bool _log,
        bool _report
    )
        Handler(_ionPool, _underlying, _registry, _log, _report)
    {
        underlying.approve(address(ionPool), type(uint256).max);
    }

    function supply(uint256 amount, uint256 warpTimeAmount) public {
        amount = bound(amount, 0, type(uint128).max);

        _warpTime(warpTimeAmount);
        (uint256 supplyFactorIncrease,,,,) = _calculateRewardAndDebtDistribution();

        uint256 amountNormalized = amount.rayDivDown(ionPool.supplyFactor() + supplyFactorIncrease);

        if (amountNormalized == 0) return;
        totalHoldingsNormalized += amountNormalized;

        if (LOG) console.log("supply", amount);

        underlying.mint(address(this), amount);
        ionPool.supply(address(this), amount, new bytes32[](0));

        if (REPORT) reportAction(Actions.SUPPLY, 0, amount);
    }

    function withdraw(uint256 amount, uint256 warpTimeAmount) public {
        // To prevent reverts, limit withdraw amounts to the available liquidity in the pool
        uint256 balance = Math.min(ionPool.weth(), ionPool.balanceOf(address(this)));
        amount = bound(amount, 0, balance);

        _warpTime(warpTimeAmount);
        (uint256 supplyFactorIncrease,,,,) = _calculateRewardAndDebtDistribution();

        uint256 amountNormalized = amount.rayDivUp(ionPool.supplyFactor() + supplyFactorIncrease);
        if (amountNormalized == 0) return;

        totalHoldingsNormalized -= amountNormalized;

        if (LOG) console.log("withdraw", amount);

        ionPool.withdraw(address(this), amount);

        if (REPORT) reportAction(Actions.WITHDRAW, 0, amount);
    }

    function _calculateRewardAndDebtDistribution()
        internal
        view
        returns (
            uint256 supplyFactorIncrease,
            uint256 treasuryMintAmount,
            uint104[] memory newRateIncreases,
            uint256 newDebtIncrease,
            uint48[] memory newTimestampIncreases
        )
    {
        uint256 ilksLength = ionPool.ilkCount();
        newRateIncreases = new uint104[](ilksLength);
        newTimestampIncreases = new uint48[](ilksLength);
        for (uint8 i = 0; i < ilksLength;) {
            (
                uint256 _supplyFactorIncrease,
                uint256 _treasuryMintAmount,
                uint104 _newRateIncrease,
                uint256 _newDebtIncrease,
                uint48 _timestampIncrease
            ) = ionPool.calculateRewardAndDebtDistribution(i);

            if (_timestampIncrease > 0) {
                newRateIncreases[i] = _newRateIncrease;
                newTimestampIncreases[i] = _timestampIncrease;
                newDebtIncrease += _newDebtIncrease;

                supplyFactorIncrease += _supplyFactorIncrease;
                treasuryMintAmount += _treasuryMintAmount;
            }

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }
    }
}

contract BorrowerHandler is Handler {
    ERC20PresetMinterPauser[] collaterals;

    constructor(
        IonPoolExposed _ionPool,
        IonRegistry _registry,
        ERC20PresetMinterPauser _underlying,
        ERC20PresetMinterPauser[] memory _collaterals,
        bool _log,
        bool _report
    )
        Handler(_ionPool, _underlying, _registry, _log, _report)
    {
        underlying.approve(address(_ionPool), type(uint256).max);
        ionPool.addOperator(address(_ionPool));
        collaterals = _collaterals;
    }

    function borrow(uint8 ilkIndex, uint256 normalizedAmount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        _warpTime(warpTimeAmount);

        uint256 ilkRate = ionPool.rate(_ilkIndex);
        uint256 maxAdditionalNormalizedDebt;
        {
            uint256 vaultCollateral = ionPool.collateral(_ilkIndex, address(this));
            uint256 ilkSpot = ionPool.spot(_ilkIndex).getSpot();
            uint256 vaultNormalizedDebt = ionPool.normalizedDebt(_ilkIndex, address(this));

            uint256 currentDebt = vaultNormalizedDebt * ilkRate;
            uint256 debtLimit = ilkSpot * vaultCollateral;

            if (currentDebt > debtLimit) return; // Position is in liquidatable state

            uint256 maxAdditionalDebt = debtLimit - currentDebt;
            maxAdditionalNormalizedDebt = _min(maxAdditionalDebt / ilkRate, type(uint64).max);
        }

        uint256 poolLiquidity = ionPool.weth();
        uint256 normalizedPoolLiquidity = poolLiquidity.rayDivDown(ilkRate);

        normalizedAmount = _min(bound(normalizedAmount, 0, maxAdditionalNormalizedDebt), normalizedPoolLiquidity);

        if (LOG) console.log("borrow", normalizedAmount);

        ionPool.borrow(_ilkIndex, address(this), address(this), normalizedAmount, new bytes32[](0));

        if (REPORT) reportAction(Actions.BORROW, _ilkIndex, normalizedAmount);
    }

    function repay(uint8 ilkIndex, uint256 normalizedAmount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        uint256 currentNormalizedDebt = ionPool.normalizedDebt(_ilkIndex, address(this));
        normalizedAmount = bound(normalizedAmount, 0, currentNormalizedDebt);

        if (LOG) console.log("repay", normalizedAmount);

        _warpTime(warpTimeAmount);
        ionPool.repay(_ilkIndex, address(this), address(this), normalizedAmount);

        if (REPORT) reportAction(Actions.REPAY, _ilkIndex, normalizedAmount);
    }

    function depositCollateral(uint8 ilkIndex, uint256 amount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        amount = bound(amount, 0, ionPool.gem(_ilkIndex, address(this)));

        if (LOG) console.log("depositCollateral", amount);

        _warpTime(warpTimeAmount);
        ionPool.depositCollateral(_ilkIndex, address(this), address(this), amount, new bytes32[](0));

        if (REPORT) reportAction(Actions.DEPOSIT_COLLATERAL, _ilkIndex, amount);
    }

    function withdrawCollateral(uint8 ilkIndex, uint256 amount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        uint256 ilkRate = ionPool.rate(_ilkIndex);
        uint256 maxRemovableCollateral;
        {
            uint256 vaultCollateral = ionPool.collateral(_ilkIndex, address(this));
            uint256 ilkSpot = ionPool.spot(_ilkIndex).getSpot();
            uint256 vaultNormalizedDebt = ionPool.normalizedDebt(_ilkIndex, address(this));

            uint256 currentDebt = vaultNormalizedDebt * ilkRate;
            uint256 minimumCollateral = currentDebt / ilkSpot;
            maxRemovableCollateral = vaultCollateral - minimumCollateral;
        }

        amount = bound(amount, 0, maxRemovableCollateral);

        if (LOG) console.log("withdrawCollateral", amount);

        _warpTime(warpTimeAmount);
        ionPool.withdrawCollateral(ilkIndex, address(this), address(this), amount);

        if (REPORT) reportAction(Actions.WITHDRAW_COLLATERAL, _ilkIndex, amount);
    }

    function gemJoin(uint8 ilkIndex, uint256 amount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));
        amount = bound(amount, 0, type(uint256).max);

        GemJoin _gemJoin = registry.gemJoins(_ilkIndex);
        ERC20PresetMinterPauser gem = collaterals[_ilkIndex];
        gem.approve(address(_gemJoin), amount);
        gem.mint(address(this), amount);

        amount = bound(amount, 0, gem.balanceOf(address(this)));

        if (amount == 0) return;
        if (LOG) console.log("gemJoin", amount);

        _warpTime(warpTimeAmount);
        _gemJoin.join(address(this), amount);

        if (REPORT) reportAction(Actions.GEM_JOIN, _ilkIndex, amount);
    }

    function gemExit(uint8 ilkIndex, uint256 amount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, ionPool.ilkCount()));

        amount = bound(amount, 0, ionPool.gem(_ilkIndex, address(this)));
        GemJoin _gemJoin = registry.gemJoins(_ilkIndex);

        if (LOG) console.log("gemExit", amount);

        _warpTime(warpTimeAmount);
        _gemJoin.exit(address(this), amount);

        if (REPORT) reportAction(Actions.GEM_EXIT, _ilkIndex, amount);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract LiquidatorHandler is Handler {
    constructor(
        IonPoolExposed _ionPool,
        IonRegistry _registry,
        ERC20PresetMinterPauser _underlying,
        bool _log,
        bool _report
    )
        Handler(_ionPool, _underlying, _registry, _log, _report)
    { }
}
