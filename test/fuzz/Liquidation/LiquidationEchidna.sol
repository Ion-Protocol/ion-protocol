// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.21;

// import { LiquidationSharedSetup } from "test/helpers/LiquidationSharedSetup.sol";
// import { Liquidation } from "src/Liquidation.sol";

// // Fuzzes the assertion in the Liquidation contract with whitelisted functions
// // Assumes that the target health, liquidation threshold, and discount is correctly set.
// // Assume targetHealth is above 1.
// // Assume targetHealth - (liquidationThreshold / 1 - discount) > 0
// // Set maxDiscount = 1 - 1 / targetHealth
// // What is the bound for exchangeRate?
// // How to make sure this is a partial liquidation scenario?
// // Bound using the partial liquidation math
// // Bound assuming dust exists
// // Bound assuming partial liquidation is not possible
// contract LiquidationEchidna is LiquidationSharedSetup {
//     address borrower;
//     address lender;
//     address keeper;

//     struct LiquidationEchidnaArgs {
//         uint256 targetHealth;
//         uint256 reserveFactor;
//         uint256 maxDiscount;
//         uint256 liquidationThreshold;
//     }

//     constructor() {
//         ilkIndex = 0;

//         // how to bound the number of borrowers/lenders?
//         // array of borrowers and lenders
//         borrower = address(1);
//         lender = address(2);
//         keeper = address(3);

//         // initialize the contract
//         // NOTE: how to fuzz contract configs?
//         // redeploy the contract with different configs
//         LiquidationEchidnaArgs memory args;
//         args.targetHealth = 1.25 ether;
//         args.maxDiscount = 0.2 ether;
//         args.liquidationThreshold = 0.8 ether;
//         args.reserveFactor = 0;

//         uint64[ILK_COUNT] memory liquidationThresholds = [uint64(args.liquidationThreshold), 0, 0, 0, 0, 0, 0, 0];
//         liquidation =
//         new Liquidation(address(ionPool), address(reserveOracle), revenueRecipient, liquidationThresholds, args.targetHealth, args.reserveFactor, args.maxDiscount);
//         ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(liquidation));
//     }

//     // --- Whitelisted Functions ---

//     // function updateConfigs() public {
//     // redpeploy liquidations contract with different configs
//     // }

//     // params
//     // change exchangeRate reported by the reserveOracle
//     // TODO: how to bound the exchangeRate?
//     function changeExchangeRate(uint256 _exchangeRate) public {
//         uint256 minExchangeRate = 0.5 ether;
//         uint256 maxExchangeRate = 1 ether;
//         _exchangeRate = minExchangeRate + (_exchangeRate % (maxExchangeRate - minExchangeRate));
//         reserveOracle.setExchangeRate(_exchangeRate);
//     }

//     // user actions
//     function borrow(uint256 _depositAmt, uint256 _borrowAmt) public {
//         borrow(borrower, ilkIndex, _depositAmt, _borrowAmt);
//     }

//     function supply(uint256 _supplyAmt) public {
//         supply(lender, _supplyAmt);
//     }

//     function liquidate() public {
//         liquidate(keeper, ilkIndex, borrower);
//     }
// }
