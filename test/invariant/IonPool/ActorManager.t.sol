// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.21;

// import { IonPoolSharedSetup } from "../../helpers/IonPoolSharedSetup.sol";
// import { IHevm } from "../../echidna/IHevm.sol";
// import { LenderHandler, BorrowerHandler, LiquidatorHandler } from "./Handlers.t.sol";
// import { safeconsole as console } from "forge-std/safeconsole.sol";

// import { CommonBase } from "forge-std/Base.sol";
// import { StdCheats } from "forge-std/StdCheats.sol";
// import { StdUtils } from "forge-std/StdUtils.sol";

// contract ActorManager is CommonBase, StdCheats, StdUtils {
//     IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

//     LenderHandler[] internal lenders;
//     BorrowerHandler[] internal borrowers;
//     LiquidatorHandler[] internal liquidators;

//     constructor(
//         LenderHandler[] memory _lenders,
//         BorrowerHandler[] memory _borrowers,
//         LiquidatorHandler[] memory _liquidators
//     ) {
//         lenders = _lenders;
//         borrowers = _borrowers;
//         liquidators = _liquidators;
//     }

//     function supply(uint256 lenderIndex, uint256 amount) public {
//         lenderIndex = bound(lenderIndex, 0, lenders.length - 1);
//         lenders[lenderIndex].supply(amount);
//     }

//     function withdraw(uint256 lenderIndex, uint256 amount) public {
//         lenderIndex = bound(lenderIndex, 0, lenders.length - 1);
//         lenders[lenderIndex].withdraw(amount);
//     }
// }

// contract IonPool_InvariantTest is IonPoolSharedSetup {
//     IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

//     uint256 internal constant AMOUNT_LENDERS = 4;
//     uint256 internal constant AMOUNT_BORROWERS = 4;
//     uint256 internal constant AMOUNT_LIQUDIATORS = 1;

//     LenderHandler[] internal lenders;
//     BorrowerHandler[] internal borrowers;
//     LiquidatorHandler[] internal liquidators;

//     ActorManager public actorManager;

//     function setUp() public virtual override {
//         // super.setUp();
//         // for (uint256 i = 0; i < AMOUNT_LENDERS; i++) {
//         //     LenderHandler lender = new LenderHandler(ionPool, underlying);
//         //     lenders.push(lender);
//         //     underlying.grantRole(underlying.MINTER_ROLE(), address(lender));
//         // }

//         // for (uint256 i = 0; i < borrowers.length; i++) {
//         //     borrowers.push(new BorrowerHandler(ionPool, ionHandler, underlying));
//         //     for (uint256 j = 0; j < collaterals.length; j++) {
//         //         collaterals[j].mint(address(borrowers[i]), INITIAL_BORROWER_COLLATERAL_BALANCE);
//         //     }
//         // }

//         // actorManager = new ActorManager(lenders, borrowers, liquidators);

//         // targetContract(address(actorManager));
//         // ionPool.changeSupplyFactor(3.564039457584007913129639935e27);
//     }

//     function invariant_lenderDepositsAddToBalance() external returns (bool) {
//         for (uint256 i = 0; i < lenders.length; i++) {
//             assertEq(lenders[i].totalHoldingsNormalized(), ionPool.normalizedBalanceOf(address(lenders[i])));
//         }
//         return !failed();
//     }

//     function invariant_lenderBalancesAddToTotalSupply() external returns (bool) {
//         uint256 totalLenderNormalizedBalances;
//         for (uint256 i = 0; i < lenders.length; i++) {
//             totalLenderNormalizedBalances += ionPool.normalizedBalanceOf(address(lenders[i]));
//         }
//         assertEq(totalLenderNormalizedBalances, ionPool.normalizedTotalSupply());
//         return !failed();
//     }

//     // function invariant_tryProperty() external returns (bool) {
//     //     return (ionPool.totalSupply() == 0);
//     // }
// }
