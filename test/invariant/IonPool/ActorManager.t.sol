// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GemJoin } from "../../../src/join/GemJoin.sol";
import { IonPool } from "../../../src/IonPool.sol";
import { WadRayMath } from "../../../src/libraries/math/WadRayMath.sol";

import { IonPoolSharedSetup } from "../../helpers/IonPoolSharedSetup.sol";
import { InvariantHelpers } from "../../helpers/InvariantHelpers.sol";

import { LenderHandler, BorrowerHandler, LiquidatorHandler } from "./Handlers.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

using WadRayMath for uint256;

contract ActorManager is CommonBase, StdCheats, StdUtils {
    IonPool ionPool;
    LenderHandler[] internal lenders;
    BorrowerHandler[] internal borrowers;
    LiquidatorHandler[] internal liquidators;

    constructor(
        IonPool _ionPool,
        LenderHandler[] memory _lenders,
        BorrowerHandler[] memory _borrowers,
        LiquidatorHandler[] memory _liquidators
    ) {
        ionPool = _ionPool;
        lenders = _lenders;
        borrowers = _borrowers;
        liquidators = _liquidators;
    }

    // For a more interesting fuzz, we will use a custom fallback dispatcher.
    function fuzzedFallback(
        uint128 userIndex,
        uint128 ilkIndex,
        uint128 amount,
        uint128 warpTimeAmount,
        uint256 functionIndex
    )
        public
    {
        uint256 globalUtilizationRate = InvariantHelpers.getUtilizationRate(ionPool);

        if (globalUtilizationRate < 0.5e45) {
            functionIndex = bound(functionIndex, 0, 4);

            if (functionIndex == 0) {
                borrow(userIndex, ilkIndex, amount, warpTimeAmount);
            } else if (functionIndex == 1) {
                depositCollateral(userIndex, ilkIndex, amount, warpTimeAmount);
            } else if (functionIndex == 2) {
                gemJoin(userIndex, ilkIndex, amount, warpTimeAmount);
            } else {
                withdraw(userIndex, amount, warpTimeAmount);
            }
        } else if (globalUtilizationRate > 0.95e45) {
            functionIndex = bound(functionIndex, 0, 4);

            if (functionIndex == 0) {
                repay(userIndex, ilkIndex, amount, warpTimeAmount);
            } else if (functionIndex == 1) {
                withdrawCollateral(userIndex, ilkIndex, amount, warpTimeAmount);
            } else if (functionIndex == 2) {
                gemExit(userIndex, ilkIndex, amount, warpTimeAmount);
            } else {
                supply(userIndex, amount, warpTimeAmount);
            }
        } else {
            functionIndex = bound(functionIndex, 0, 8);

            if (functionIndex == 0) {
                borrow(userIndex, ilkIndex, amount, warpTimeAmount);
            } else if (functionIndex == 1) {
                depositCollateral(userIndex, ilkIndex, amount, warpTimeAmount);
            } else if (functionIndex == 2) {
                gemJoin(userIndex, ilkIndex, amount, warpTimeAmount);
            } else if (functionIndex == 3) {
                withdraw(userIndex, amount, warpTimeAmount);
            } else if (functionIndex == 4) {
                repay(userIndex, ilkIndex, amount, warpTimeAmount);
            } else if (functionIndex == 5) {
                withdrawCollateral(userIndex, ilkIndex, amount, warpTimeAmount);
            } else if (functionIndex == 6) {
                gemExit(userIndex, ilkIndex, amount, warpTimeAmount);
            } else {
                supply(userIndex, amount, warpTimeAmount);
            }
        }
    }

    function supply(uint128 lenderIndex, uint128 amount, uint128 warpTimeAmount) internal {
        lenderIndex = uint128(bound(lenderIndex, 0, lenders.length - 1));
        lenders[lenderIndex].supply(amount, warpTimeAmount);
    }

    function withdraw(uint128 lenderIndex, uint128 amount, uint128 warpTimeAmount) internal {
        lenderIndex = uint128(bound(lenderIndex, 0, lenders.length - 1));
        lenders[lenderIndex].withdraw(amount, warpTimeAmount);
    }

    function borrow(uint128 borrowerIndex, uint128 ilkIndex, uint128 amount, uint128 warpTimeAmount) internal {
        borrowerIndex = uint128(bound(borrowerIndex, 0, borrowers.length - 1));
        ilkIndex = uint128(bound(ilkIndex, 0, ionPool.ilkCount() - 1));

        borrowers[borrowerIndex].borrow(uint8(ilkIndex), amount, warpTimeAmount);
    }

    function repay(uint128 borrowerIndex, uint128 ilkIndex, uint128 amount, uint128 warpTimeAmount) internal {
        borrowerIndex = uint128(bound(borrowerIndex, 0, borrowers.length - 1));
        ilkIndex = uint128(bound(ilkIndex, 0, ionPool.ilkCount() - 1));

        borrowers[borrowerIndex].repay(uint8(ilkIndex), amount, warpTimeAmount);
    }

    function depositCollateral(
        uint128 borrowerIndex,
        uint128 ilkIndex,
        uint128 amount,
        uint128 warpTimeAmount
    )
        internal
    {
        borrowerIndex = uint128(bound(borrowerIndex, 0, borrowers.length - 1));
        ilkIndex = uint128(bound(ilkIndex, 0, ionPool.ilkCount() - 1));

        borrowers[borrowerIndex].depositCollateral(uint8(ilkIndex), amount, warpTimeAmount);
    }

    function withdrawCollateral(
        uint128 borrowerIndex,
        uint128 ilkIndex,
        uint128 amount,
        uint128 warpTimeAmount
    )
        internal
    {
        borrowerIndex = uint128(bound(borrowerIndex, 0, borrowers.length - 1));
        ilkIndex = uint128(bound(ilkIndex, 0, ionPool.ilkCount() - 1));

        borrowers[borrowerIndex].withdrawCollateral(uint8(ilkIndex), amount, warpTimeAmount);
    }

    function gemJoin(uint128 borrowerIndex, uint128 ilkIndex, uint128 amount, uint128 warpTimeAmount) internal {
        borrowerIndex = uint128(bound(borrowerIndex, 0, borrowers.length - 1));
        ilkIndex = uint128(bound(ilkIndex, 0, ionPool.ilkCount() - 1));

        borrowers[borrowerIndex].gemJoin(uint8(ilkIndex), amount, warpTimeAmount);
    }

    function gemExit(uint128 borrowerIndex, uint128 ilkIndex, uint128 amount, uint128 warpTimeAmount) internal {
        borrowerIndex = uint128(bound(borrowerIndex, 0, borrowers.length - 1));
        ilkIndex = uint128(bound(ilkIndex, 0, ionPool.ilkCount() - 1));

        borrowers[borrowerIndex].gemExit(uint8(ilkIndex), amount, warpTimeAmount);
    }
}

contract IonPool_InvariantTest is IonPoolSharedSetup {
    uint256 internal constant AMOUNT_LENDERS = 2;
    uint256 internal constant AMOUNT_BORROWERS = 2;
    uint256 internal constant AMOUNT_LIQUDIATORS = 1;

    LenderHandler[] internal lenders;
    BorrowerHandler[] internal borrowers;
    LiquidatorHandler[] internal liquidators;

    ActorManager public actorManager;

    uint256 internal constant INITIAL_LENDER_SUPPLY_AMOUNT = 500e18;
    uint256 internal constant INITIAL_BORROWER_GEM_JOIN_AMOUNT = 500e18;
    uint256 internal constant INITIAL_BORROWER_BORROW_AMOUNT = 10e18;

    function setUp() public virtual override {
        bool log = vm.envOr("LOG", uint256(0)) == 1;
        bool report = vm.envOr("REPORT", uint256(0)) == 1;
        _setUp(log, report);
    }

    function _setUp(bool log, bool report) internal {
        super.setUp();

        // Disable debt ceiling
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, _getDebtCeiling(i));
        }

        for (uint256 i = 0; i < AMOUNT_LENDERS; i++) {
            LenderHandler lender = new LenderHandler(ionPool,ionRegistry, underlying, distributionFactors, log, report);
            lenders.push(lender);
            underlying.grantRole(underlying.MINTER_ROLE(), address(lender));

            // Initialize with some liquidity
            lender.supply(INITIAL_LENDER_SUPPLY_AMOUNT, 0);
        }

        for (uint256 i = 0; i < AMOUNT_BORROWERS; i++) {
            BorrowerHandler borrower =
            new BorrowerHandler(ionPool, ionRegistry, underlying, mintableCollaterals, distributionFactors, log, report);
            borrowers.push(borrower);
            for (uint8 j = 0; j < collaterals.length; j++) {
                mintableCollaterals[j].grantRole(mintableCollaterals[j].MINTER_ROLE(), address(borrowers[i]));

                // Initialize with a borrow position
                borrower.gemJoin(j, INITIAL_BORROWER_GEM_JOIN_AMOUNT, 0);
                borrower.depositCollateral(j, INITIAL_BORROWER_GEM_JOIN_AMOUNT, 0);
                borrower.borrow(j, INITIAL_BORROWER_BORROW_AMOUNT, 0);
            }
        }
        actorManager = new ActorManager(ionPool, lenders, borrowers, liquidators);

        targetContract(address(actorManager));
    }

    function invariant_LenderDepositsAddToBalance() external returns (bool) {
        for (uint256 i = 0; i < lenders.length; i++) {
            assertEq(lenders[i].totalHoldingsNormalized(), ionPool.normalizedBalanceOf(address(lenders[i])));
        }

        return !failed();
    }

    function invariant_LenderBalancesPlusTreasuryAddToTotalSupply() external returns (bool) {
        uint256 totalLenderNormalizedBalances;
        for (uint256 i = 0; i < lenders.length; i++) {
            totalLenderNormalizedBalances += ionPool.normalizedBalanceOf(address(lenders[i]));
        }
        assertEq(totalLenderNormalizedBalances + ionPool.normalizedBalanceOf(TREASURY), ionPool.normalizedTotalSupply());

        return !failed();
    }

    function invariant_LiquidityInPoolPlusDebtToPoolStrictlyGreaterThanOrEqualToTotalSupply() external returns (bool) {
        uint256 totalDebt;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 totalNormalizedDebts;
            for (uint256 j = 0; j < borrowers.length; j++) {
                totalNormalizedDebts += ionPool.normalizedDebt(i, address(borrowers[j]));
            }
            uint256 ilkRate = ionPool.rate(i);
            totalDebt += totalNormalizedDebts.rayMulDown(ilkRate);
        }
        assertGe(ionPool.weth() + totalDebt, ionPool.totalSupply());
        assertGe(
            ionPool.weth().scaleUpToRad(18) + ionPool.debt(), ionPool.normalizedTotalSupply() * ionPool.supplyFactor()
        );

        return !failed();
    }

    function invariant_BorrowerNormalizedDebtsSumToTotalNormalizedDebt() external returns (bool) {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 sumBorrowerNormalizedDebts;
            for (uint256 j = 0; j < borrowers.length; j++) {
                sumBorrowerNormalizedDebts += ionPool.normalizedDebt(i, address(borrowers[j]));
            }
            assertEq(sumBorrowerNormalizedDebts, ionPool.totalNormalizedDebt(i));
        }

        return !failed();
    }

    function invariant_SumOfAllGemAndCollateralEqualsTotalGemInGemJoin() external returns (bool) {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gemAndCollateralSum;
            for (uint256 j = 0; j < borrowers.length; j++) {
                gemAndCollateralSum += ionPool.gem(i, address(borrowers[j]));
            }
            for (uint256 j = 0; j < borrowers.length; j++) {
                gemAndCollateralSum += ionPool.collateral(i, address(borrowers[j]));
            }
            GemJoin gemJoin = ionRegistry.gemJoins(i);
            assertEq(gemAndCollateralSum, gemJoin.totalGem());
        }

        return !failed();
    }

    function invariant_SumOfAllIlkTotalNormalizedDebtTimesIlkRatePlusUnbackedDebtEqualsTotalDebt()
        external
        returns (bool)
    {
        uint256 totalDebt;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 totalNormalizedDebt = ionPool.totalNormalizedDebt(i);
            uint256 ilkRate = ionPool.rate(i);
            totalDebt += totalNormalizedDebt * ilkRate;
        }
        assertEq(totalDebt + ionPool.totalUnbackedDebt(), ionPool.debt());

        return !failed();
    }

    /// forge-config: default.invariant.runs = 1
    function invariantFoundry_report() external { }

    function _getDebtCeiling(uint8) internal pure override returns (uint256) {
        return type(uint256).max;
    }
}
