// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.21;

// import { IonPool } from "../IonPool.sol";
// import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
// import { RoundedMath } from "../math/RoundedMath.sol";
// import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
// import { safeconsole as console } from "forge-std/safeconsole.sol";

// // TODO: DELETE
// contract IonHandler {
//     using RoundedMath for uint256;
//     using SafeCast for uint256;

//     IonPool immutable ionPool;
//     IERC20 immutable base;

//     constructor(IonPool _ionPool) {
//         ionPool = _ionPool;
//         IERC20 _base = ionPool.underlying();
//         base = _base;

//         _base.approve(address(ionPool), type(uint256).max);
//     }

//     // --- Borrower Operations ---

//     /**
//      * @param ilkIndex index of the collateral to borrow again
//      * @param amount amount to borrow
//      */
//     function borrow(uint8 ilkIndex, uint256 amount) external {
//         uint256 _rate = ionPool.rate(ilkIndex);
//         uint256 normalizedAmount = amount.rayDivDown(_rate); // [WAD] * [RAY] / [RAY] = [WAD]

//     }

//     function repay(uint8 ilkIndex, uint256 amount) external {
//         uint256 _rate = ionPool.rate(ilkIndex);
//         uint256 normalizedAmount = amount.rayDivDown(_rate);
//         uint256 trueAmount = normalizedAmount.rayMulDown(_rate);

//         base.transferFrom(msg.sender, address(this), trueAmount);
//     }
// }
