// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GemJoin } from "src/join/GemJoin.sol";
import { IonPool } from "src/IonPool.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";

import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";
import { IHevm } from "test/helpers/echidna/IHevm.sol";

import { LenderHandler, BorrowerHandler, LiquidatorHandler } from "./Handlers.t.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";
import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

using RoundedMath for uint256;

contract ActorManager is CommonBase, StdCheats, StdUtils {
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

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

    function supply(uint256 lenderIndex, uint256 amount) public {
        lenderIndex = bound(lenderIndex, 0, lenders.length - 1);
        lenders[lenderIndex].supply(amount);
    }

    function withdraw(uint256 lenderIndex, uint256 amount) public {
        lenderIndex = bound(lenderIndex, 0, lenders.length - 1);
        lenders[lenderIndex].withdraw(amount);
    }

    function borrow(uint256 borrowerIndex, uint256 ilkIndex, uint128 amount) public {
        borrowerIndex = bound(borrowerIndex, 0, borrowers.length - 1);
        ilkIndex = bound(ilkIndex, 0, ionPool.ilkCount() - 1);

        borrowers[borrowerIndex].borrow(uint8(ilkIndex), amount);
    }

    function repay(uint256 borrowerIndex, uint256 ilkIndex, uint128 amount) public {
        borrowerIndex = bound(borrowerIndex, 0, borrowers.length - 1);
        ilkIndex = bound(ilkIndex, 0, ionPool.ilkCount() - 1);

        borrowers[borrowerIndex].repay(uint8(ilkIndex), amount);
    }

    function depositCollateral(uint256 borrowerIndex, uint256 ilkIndex, uint128 amount) public {
        borrowerIndex = bound(borrowerIndex, 0, borrowers.length - 1);
        ilkIndex = bound(ilkIndex, 0, ionPool.ilkCount() - 1);

        borrowers[borrowerIndex].depositCollateral(uint8(ilkIndex), amount);
    }

    function withdrawCollateral(uint256 borrowerIndex, uint256 ilkIndex, uint128 amount) public {
        borrowerIndex = bound(borrowerIndex, 0, borrowers.length - 1);
        ilkIndex = bound(ilkIndex, 0, ionPool.ilkCount() - 1);

        borrowers[borrowerIndex].withdrawCollateral(uint8(ilkIndex), amount);
    }

    function gemJoin(uint256 borrowerIndex, uint256 ilkIndex, uint128 amount) public {
        borrowerIndex = bound(borrowerIndex, 0, borrowers.length - 1);
        ilkIndex = bound(ilkIndex, 0, ionPool.ilkCount() - 1);

        borrowers[borrowerIndex].gemJoin(uint8(ilkIndex), amount);
    }

    function gemExit(uint256 borrowerIndex, uint256 ilkIndex, uint128 amount) public {
        borrowerIndex = bound(borrowerIndex, 0, borrowers.length - 1);
        ilkIndex = bound(ilkIndex, 0, ionPool.ilkCount() - 1);

        borrowers[borrowerIndex].gemExit(uint8(ilkIndex), amount);
    }
}

contract IonPool_InvariantTest is IonPoolSharedSetup {
    IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 internal constant AMOUNT_LENDERS = 4;
    uint256 internal constant AMOUNT_BORROWERS = 4;
    uint256 internal constant AMOUNT_LIQUDIATORS = 1;

    LenderHandler[] internal lenders;
    BorrowerHandler[] internal borrowers;
    LiquidatorHandler[] internal liquidators;

    ActorManager public actorManager;

    function setUp() public virtual override {
        bool log = vm.envOr("LOG", uint256(0)) == 1;
        _setUp(log);
    }

    function _setUp(bool log) internal {
        super.setUp();

        for (uint256 i = 0; i < AMOUNT_LENDERS; i++) {
            LenderHandler lender = new LenderHandler(ionPool, underlying, log);
            lenders.push(lender);
            underlying.grantRole(underlying.MINTER_ROLE(), address(lender));
        }

        for (uint256 i = 0; i < AMOUNT_BORROWERS; i++) {
            borrowers.push(new BorrowerHandler(ionPool, ionRegistry, underlying, mintableCollaterals, log));
            for (uint256 j = 0; j < collaterals.length; j++) {
                mintableCollaterals[j].grantRole(mintableCollaterals[j].MINTER_ROLE(), address(borrowers[i]));
            }
        }

        // Disable debt ceiling
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        actorManager = new ActorManager(ionPool, lenders, borrowers, liquidators);

        targetContract(address(actorManager));
        ionPool.setSupplyFactor(3.564039457584007913129639935e27);
    }

    function invariant_lenderDepositsAddToBalance() external returns (bool) {
        for (uint256 i = 0; i < lenders.length; i++) {
            assertEq(lenders[i].totalHoldingsNormalized(), ionPool.normalizedBalanceOf(address(lenders[i])));
        }

        return !failed();
    }

    function invariant_lenderBalancesAddToTotalSupply() external returns (bool) {
        uint256 totalLenderNormalizedBalances;
        for (uint256 i = 0; i < lenders.length; i++) {
            totalLenderNormalizedBalances += ionPool.normalizedBalanceOf(address(lenders[i]));
        }
        assertEq(totalLenderNormalizedBalances, ionPool.normalizedTotalSupply());

        return !failed();
    }

    function invariant_underlyingBalanceOfPoolPlusDebtToPoolStrictlyGreaterThanOrEqualToTotalSupply()
        external
        returns (bool)
    {
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

        return !failed();
    }

    function invariant_borrowerNormalizedDebtsSumToTotalNormalizedDebt() external returns (bool) {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 sumBorrowerNormalizedDebts;
            for (uint256 j = 0; j < borrowers.length; j++) {
                sumBorrowerNormalizedDebts += ionPool.normalizedDebt(i, address(borrowers[j]));
            }
            assertEq(sumBorrowerNormalizedDebts, ionPool.totalNormalizedDebt(i));
        }

        return !failed();
    }

    function invariant_sumOfAllGemAndCollateralEqualsBalanceOfGemJoin() external returns (bool) {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 gemAndCollateralSum;
            for (uint256 j = 0; j < borrowers.length; j++) {
                gemAndCollateralSum += ionPool.gem(i, address(borrowers[j]));
            }
            for (uint256 j = 0; j < borrowers.length; j++) {
                gemAndCollateralSum += ionPool.collateral(i, address(borrowers[j]));
            }
            GemJoin gemJoin = ionRegistry.gemJoins(i);
            IERC20 gem = gemJoin.gem();
            assertEq(gemAndCollateralSum, gem.balanceOf(address(gemJoin)));
        }

        return !failed();
    }

    function invariant_sumOfAllVaultNormalizedDebtEqualsIlkTotalNormalizedDebt() external returns (bool) {
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 sumVaultNormalizedDebt;
            for (uint256 j = 0; j < borrowers.length; j++) {
                sumVaultNormalizedDebt += ionPool.normalizedDebt(i, address(borrowers[j]));
            }
            assertEq(sumVaultNormalizedDebt, ionPool.totalNormalizedDebt(i));
        }

        return !failed();
    }

    function invariantFoundry_report() external returns (bool) {
        return true;
    }
}
