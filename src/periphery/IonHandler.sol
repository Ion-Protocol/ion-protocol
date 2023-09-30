// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IonPool } from "../IonPool.sol";
import { RoundedMath } from "../math/RoundedMath.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract IonHandler {
    using RoundedMath for uint256;
    using SafeCast for uint256;

    IonPool immutable ionPool;

    constructor(IonPool _ionPool) {
        ionPool = _ionPool;
    }

    // --- Borrower Operations ---

    /**
     * @param ilkIndex index of the collateral to borrow again
     * @param amount amount to borrow
     */
    function borrow(uint8 ilkIndex, uint256 amount) external {
        uint256 normalizedAmount = amount.roundedRayDiv(ionPool.rate(ilkIndex)); // [WAD] * [RAY] / [RAY] = [WAD]

        // Moves all gem into the vault ink
        ionPool.modifyPosition(
            ilkIndex,
            msg.sender,
            msg.sender,
            msg.sender,
            ionPool.gem(ilkIndex, msg.sender).toInt256(), // Move all gem into the vault as collateral
            normalizedAmount.toInt256()
        );

        ionPool.exitBase(msg.sender, amount);
    }

    function repay(uint8 ilkIndex, uint256 amount) external {
        uint256 normalizedAmount = amount.roundedRayDiv(ionPool.rate(ilkIndex));

        ionPool.joinBase(msg.sender, amount);

        ionPool.modifyPosition(ilkIndex, msg.sender, msg.sender, msg.sender, 0, -normalizedAmount.toInt256());
    }
}
