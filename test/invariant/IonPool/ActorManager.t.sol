// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.19;

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
//         lenderIndex = bound(lenderIndex, 0, lenders.length);
//         lenders[lenderIndex].supply(address(lenders[lenderIndex]), amount);
//     }
// }

// contract IonPoolInvariantTest is IonPoolSharedSetup {
//     IHevm hevm = IHevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

//     uint256 internal constant AMOUNT_LENDERS = 4;
//     uint256 internal constant AMOUNT_BORROWERS = 4;
//     uint256 internal constant AMOUNT_LIQUDIATORS = 1;

//     LenderHandler[] internal lenders;
//     BorrowerHandler[] internal borrowers;
//     LiquidatorHandler[] internal liquidators;

//     ActorManager manager;

//     function setUp() public virtual override {
//         super.setUp();
//         for (uint256 i = 0; i < AMOUNT_LENDERS; i++) {
//             lenders.push(new LenderHandler(ionPool, underlying));
//             underlying.mint(address(lenders[i]), INITIAL_LENDER_UNDERLYING_BALANCE);
//         }

//         for (uint256 i = 0; i < borrowers.length; i++) {
//             borrowers.push(new BorrowerHandler(ionPool, underlying));
//             for (uint256 j = 0; j < collaterals.length; j++) {
//                 collaterals[j].mint(address(borrowers[i]), INITIAL_BORROWER_UNDERLYING_BALANCE);
//             }
//         }

//         manager = new ActorManager(lenders, borrowers, liquidators);

//         targetContract(address(manager));
//     }

//     function invariant_tryProperty() external returns (bool) {
//         return _checkProperty(ionPool.totalSupply() == 0);
//     }

//     function _checkProperty(bool property) internal returns (bool) {
//         assertEq(property, true);
//         return property;
//     }
// }
