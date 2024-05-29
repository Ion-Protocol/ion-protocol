// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WadRayMath, RAY } from "../../../src/libraries/math/WadRayMath.sol";
import { IonRegistry } from "../../../src/periphery/IonRegistry.sol";
import { GemJoin } from "../../../src/join/GemJoin.sol";
import { SECONDS_IN_A_YEAR } from "../../../src/InterestRate.sol";
import { IIonLens } from "../../../src/interfaces/IIonLens.sol";
import { IIonPool } from "../../../src/interfaces/IIonPool.sol";
import { ISpotOracle } from "../../../src/interfaces/ISpotOracle.sol";

import { IonPoolExposed } from "../../helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "../../helpers/ERC20PresetMinterPauser.sol";
import { HEVM } from "../../helpers/echidna/IHevm.sol";
import { InvariantHelpers } from "../../helpers/InvariantHelpers.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { LibString } from "solady/src/utils/LibString.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

using WadRayMath for uint256;
using WadRayMath for uint16;
using LibString for string;
using Strings for uint256;
using Strings for uint8;

library DecimalToFixedPoint {
    function toFixedPointString(uint256 value, uint256 scale) internal pure returns (string memory) {
        uint256 tenScale = 10 ** scale;

        string memory valueAsString = value.toString();
        string memory integerPartAsString = value / tenScale == 0 ? "0" : (value / tenScale).toString();

        uint256 valueLength = bytes(valueAsString).length;
        if (valueLength >= scale) {
            return integerPartAsString.concat(string.concat(".", (valueAsString.slice(valueLength - scale))));
        } else {
            return integerPartAsString.concat(
                string.concat(".", string(bytes("0")).repeat(scale - valueLength), valueAsString)
            );
        }
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
    IIonPool internal immutable iIonPool;
    IIonLens internal immutable lens;
    ERC20PresetMinterPauser internal immutable underlying;
    IonRegistry internal immutable registry;

    uint16[] internal distributionFactors;

    bool immutable LOG;
    bool immutable REPORT;
    string internal constant REPORT_FILE = "report.csv";

    function _warpTime(uint256 warpTimeAmount) internal {
        warpTimeAmount = bound(warpTimeAmount, 100, 10_000);
        HEVM.warp(block.timestamp + warpTimeAmount);
    }

    constructor(
        IonPoolExposed _ionPool,
        IIonLens _lens,
        ERC20PresetMinterPauser _underlying,
        IonRegistry _registry,
        uint16[] memory _distributionFactors,
        bool _log,
        bool _report
    ) {
        ionPool = _ionPool;
        iIonPool = IIonPool(address(_ionPool));
        lens = _lens;
        underlying = _underlying;
        registry = _registry;
        distributionFactors = _distributionFactors;

        LOG = _log;
        REPORT = _report;
    }

    struct GlobalPoolState {
        uint256 supplyFactor;
        uint256 totalSupply;
        uint256 totalDebt;
        uint256 wethLiquidity;
        uint256 utilizationRate;
    }

    struct IlkIndexedPoolState {
        uint256 totalNormalizedDebt;
        uint256 rate;
        uint256 totalGem;
        uint256 newInterestRatePerSecond;
        uint256 newInterestRatePerYear;
        uint256 utilizationRate;
    }

    function reportAction(Actions actions, uint8 ilkIndex, uint256 amount) internal {
        vm.writeLine(REPORT_FILE, "Action, IlkIndex, Amount");

        if (actions == Actions.SUPPLY) {
            vm.writeLine(REPORT_FILE, string.concat("SUPPLY, ", "-, ", amount.toFixedPointString(18)));
        } else if (actions == Actions.WITHDRAW) {
            vm.writeLine(REPORT_FILE, string.concat("WITHDRAW, ", "-, ", amount.toFixedPointString(18)));
        } else if (actions == Actions.BORROW) {
            vm.writeLine(
                REPORT_FILE, string.concat("BORROW, ", ilkIndex.toString(), ", ", amount.toFixedPointString(18))
            );
        } else if (actions == Actions.REPAY) {
            vm.writeLine(
                REPORT_FILE, string.concat("REPAY, ", ilkIndex.toString(), ", ", amount.toFixedPointString(18))
            );
        } else if (actions == Actions.DEPOSIT_COLLATERAL) {
            vm.writeLine(
                REPORT_FILE,
                string.concat("DEPOSIT_COLLATERAL, ", ilkIndex.toString(), ", ", amount.toFixedPointString(18))
            );
        } else if (actions == Actions.WITHDRAW_COLLATERAL) {
            vm.writeLine(
                REPORT_FILE,
                string.concat("WITHDRAW_COLLATERAL, ", ilkIndex.toString(), ", ", amount.toFixedPointString(18))
            );
        } else if (actions == Actions.GEM_JOIN) {
            vm.writeLine(
                REPORT_FILE, string.concat("GEM_JOIN, ", ilkIndex.toString(), ", ", amount.toFixedPointString(18))
            );
        } else if (actions == Actions.GEM_EXIT) {
            vm.writeLine(
                REPORT_FILE, string.concat("GEM_EXIT, ", ilkIndex.toString(), ", ", amount.toFixedPointString(18))
            );
        }

        GlobalPoolState memory globalState;
        IlkIndexedPoolState[3] memory ilkIndexedState;

        globalState.supplyFactor = ionPool.supplyFactor();
        globalState.totalSupply = ionPool.totalSupply();
        globalState.totalDebt = lens.debt(iIonPool);
        globalState.wethLiquidity = lens.liquidity(iIonPool);
        globalState.utilizationRate = InvariantHelpers.getUtilizationRate(ionPool, lens);

        require(
            ilkIndexedState.length == lens.ilkCount(iIonPool), "invariant/IonPool/Handlers.t.sol: Ilk count mismatch"
        );
        for (uint256 i = 0; i < ilkIndexedState.length; ++i) {
            uint8 _ilkIndex = uint8(i);
            ilkIndexedState[i].totalNormalizedDebt = lens.totalNormalizedDebt(iIonPool, _ilkIndex);
            ilkIndexedState[i].rate = ionPool.rate(_ilkIndex);
            ilkIndexedState[i].totalGem = registry.gemJoins(_ilkIndex).totalGem();
            (uint256 currentBorrowRate,) = ionPool.getCurrentBorrowRate(_ilkIndex);
            ilkIndexedState[i].newInterestRatePerSecond = currentBorrowRate;
            ilkIndexedState[i].newInterestRatePerYear = ((currentBorrowRate - RAY) * SECONDS_IN_A_YEAR) + RAY;
            ilkIndexedState[i].utilizationRate =
                InvariantHelpers.getIlkSpecificUtilizationRate(ionPool, lens, distributionFactors, _ilkIndex);
        }

        vm.writeLine(REPORT_FILE, "");
        vm.writeLine(REPORT_FILE, "GLOBAL STATE CHANGES");
        vm.writeLine(REPORT_FILE, "Supply Factor, Total Supply, Total Debt, WETH Liquidity, Utilization Rate");
        vm.writeLine(
            REPORT_FILE,
            string.concat(
                globalState.supplyFactor.toFixedPointString(27),
                ", ",
                globalState.totalSupply.toFixedPointString(18),
                ", ",
                globalState.totalDebt.toFixedPointString(45),
                ", ",
                globalState.wethLiquidity.toFixedPointString(18),
                ", ",
                globalState.utilizationRate.toFixedPointString(45)
            )
        );

        vm.writeLine(REPORT_FILE, "");
        vm.writeLine(REPORT_FILE, "ILK STATE CHANGES");
        for (uint256 i = 0; i < ilkIndexedState.length; ++i) {
            vm.writeLine(REPORT_FILE, string.concat("ILK", i.toString()));
            vm.writeLine(
                REPORT_FILE,
                "Total Normalized Debt, Total Gem, Rate, New Interest Rate (per sec), New Interest Rate (per year), Utilization Rate"
            );
            vm.writeLine(
                REPORT_FILE,
                string.concat(
                    ilkIndexedState[i].totalNormalizedDebt.toFixedPointString(18),
                    ", ",
                    ilkIndexedState[i].totalGem.toFixedPointString(18),
                    ", ",
                    ilkIndexedState[i].rate.toFixedPointString(27),
                    ", ",
                    ilkIndexedState[i].newInterestRatePerSecond.toFixedPointString(27),
                    ", ",
                    ilkIndexedState[i].newInterestRatePerYear.toFixedPointString(27),
                    ", ",
                    ilkIndexedState[i].utilizationRate.toFixedPointString(27)
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
        IIonLens _lens,
        IonRegistry _registry,
        ERC20PresetMinterPauser _underlying,
        uint16[] memory _distributionFactors,
        bool _log,
        bool _report
    )
        Handler(_ionPool, _lens, _underlying, _registry, _distributionFactors, _log, _report)
    {
        underlying.approve(address(ionPool), type(uint256).max);
    }

    function supply(uint256 amount, uint256 warpTimeAmount) public {
        amount = bound(amount, 0, type(uint128).max);

        _warpTime(warpTimeAmount);

        uint256 amountNormalized = amount.rayDivDown(ionPool.supplyFactor());

        if (amountNormalized == 0) return;
        totalHoldingsNormalized += amountNormalized;

        if (LOG) console.log("supply", amount);

        underlying.mint(address(this), amount);
        ionPool.supply(address(this), amount, new bytes32[](0));

        if (REPORT) reportAction(Actions.SUPPLY, 0, amount);
    }

    function withdraw(uint256 amount, uint256 warpTimeAmount) public {
        // To prevent reverts, limit withdraw amounts to the available liquidity in the pool
        uint256 balance = Math.min(lens.liquidity(iIonPool), ionPool.balanceOf(address(this)));
        amount = bound(amount, 0, balance);

        _warpTime(warpTimeAmount);

        uint256 amountNormalized = amount.rayDivUp(ionPool.supplyFactor());
        if (amountNormalized == 0) return;

        totalHoldingsNormalized -= amountNormalized;

        if (LOG) console.log("withdraw", amount);

        ionPool.withdraw(address(this), amount);

        if (REPORT) reportAction(Actions.WITHDRAW, 0, amount);
    }
}

contract BorrowerHandler is Handler {
    ERC20PresetMinterPauser[] collaterals;

    constructor(
        IonPoolExposed _ionPool,
        IIonLens _lens,
        IonRegistry _registry,
        ERC20PresetMinterPauser _underlying,
        ERC20PresetMinterPauser[] memory _collaterals,
        uint16[] memory _distributionFactors,
        bool _log,
        bool _report
    )
        Handler(_ionPool, _lens, _underlying, _registry, _distributionFactors, _log, _report)
    {
        underlying.approve(address(_ionPool), type(uint256).max);
        ionPool.addOperator(address(_ionPool));
        collaterals = _collaterals;
    }

    function borrow(uint8 ilkIndex, uint256 normalizedAmount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, lens.ilkCount(iIonPool)));

        _warpTime(warpTimeAmount);

        uint256 ilkRate = ionPool.rate(_ilkIndex);
        uint256 maxAdditionalNormalizedDebt;
        {
            uint256 vaultCollateral = ionPool.collateral(_ilkIndex, address(this));
            uint256 ilkSpot = ISpotOracle(lens.spot(iIonPool, _ilkIndex)).getSpot();
            uint256 vaultNormalizedDebt = ionPool.normalizedDebt(_ilkIndex, address(this));

            uint256 currentDebt = vaultNormalizedDebt * ilkRate;
            uint256 debtLimit = ilkSpot * vaultCollateral;

            if (currentDebt > debtLimit) return; // Position is in liquidatable state

            uint256 maxAdditionalDebt = debtLimit - currentDebt;
            maxAdditionalNormalizedDebt = _min(maxAdditionalDebt / ilkRate, type(uint64).max);
        }

        uint256 poolLiquidity = lens.liquidity(iIonPool);
        uint256 normalizedPoolLiquidity = poolLiquidity.rayDivDown(ilkRate);

        normalizedAmount = _min(bound(normalizedAmount, 0, maxAdditionalNormalizedDebt), normalizedPoolLiquidity);

        if (LOG) console.log("borrow", normalizedAmount);

        ionPool.borrow(_ilkIndex, address(this), address(this), normalizedAmount, new bytes32[](0));

        if (REPORT) reportAction(Actions.BORROW, _ilkIndex, normalizedAmount);
    }

    function repay(uint8 ilkIndex, uint256 normalizedAmount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, lens.ilkCount(iIonPool)));

        uint256 currentNormalizedDebt = ionPool.normalizedDebt(_ilkIndex, address(this));
        normalizedAmount = bound(normalizedAmount, 0, currentNormalizedDebt);

        if (LOG) console.log("repay", normalizedAmount);

        _warpTime(warpTimeAmount);
        ionPool.repay(_ilkIndex, address(this), address(this), normalizedAmount);

        if (REPORT) reportAction(Actions.REPAY, _ilkIndex, normalizedAmount);
    }

    function depositCollateral(uint8 ilkIndex, uint256 amount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, lens.ilkCount(iIonPool)));

        amount = bound(amount, 0, lens.gem(iIonPool, _ilkIndex, address(this)));

        if (LOG) console.log("depositCollateral", amount);

        _warpTime(warpTimeAmount);
        ionPool.depositCollateral(_ilkIndex, address(this), address(this), amount, new bytes32[](0));

        if (REPORT) reportAction(Actions.DEPOSIT_COLLATERAL, _ilkIndex, amount);
    }

    function withdrawCollateral(uint8 ilkIndex, uint256 amount, uint256 warpTimeAmount) public {
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, lens.ilkCount(iIonPool)));

        uint256 ilkRate = ionPool.rate(_ilkIndex);
        uint256 maxRemovableCollateral;
        {
            uint256 vaultCollateral = ionPool.collateral(_ilkIndex, address(this));
            uint256 ilkSpot = ISpotOracle(lens.spot(iIonPool, _ilkIndex)).getSpot();
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
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, lens.ilkCount(iIonPool)));
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
        uint8 _ilkIndex = uint8(bound(ilkIndex, 0, lens.ilkCount(iIonPool)));

        amount = bound(amount, 0, lens.gem(iIonPool, _ilkIndex, address(this)));
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
        IIonLens lens,
        IonRegistry _registry,
        ERC20PresetMinterPauser _underlying,
        uint16[] memory _distributionFactors,
        bool _log,
        bool _report
    )
        Handler(_ionPool, lens, _underlying, _registry, _distributionFactors, _log, _report)
    { }
}
