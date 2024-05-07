// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../IonPool.sol";
import { WadRayMath } from "../libraries/math/WadRayMath.sol";

/**
 * @notice This contract will be deployed on mainnet and be used to check the
 * invariants of the Ion system offchain every block.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract IonInvariants {
    using WadRayMath for uint256;

    /**
     * @notice Liquidity in pool + debt to pool >= total supply.
     */
    function Invariant1(IonPool ionPool) external view {
        require(
            ionPool.weth().scaleUpToRad(18) + ionPool.debtUnaccrued()
                >= ionPool.normalizedTotalSupplyUnaccrued() * ionPool.supplyFactorUnaccrued()
        );
    }

    /**
     * @notice [Sum of all (ilk total normalized debt * ilk rate)] + unbacked debt >= debt to pool.
     */
    function Invariant2(IonPool ionPool) external view {
        uint256 totalDebt;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 totalNormalizedDebt = ionPool.totalNormalizedDebt(i);
            uint256 ilkRate = ionPool.rateUnaccrued(i);
            totalDebt += totalNormalizedDebt * ilkRate;
        }
        require(totalDebt + ionPool.totalUnbackedDebt() == ionPool.debtUnaccrued());
    }

    /**
     * @notice Invariant1 accrued
     */
    function Invariant3(IonPool ionPool) external view {
        require(
            ionPool.weth().scaleUpToRad(18) + ionPool.debt() >= ionPool.normalizedTotalSupply() * ionPool.supplyFactor()
        );
    }

    /**
     * @notice Invariant2 accrued
     */
    function Invariant4(IonPool ionPool) external view {
        uint256 totalDebt;
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            uint256 totalNormalizedDebt = ionPool.totalNormalizedDebt(i);
            uint256 ilkRate = ionPool.rate(i);
            totalDebt += totalNormalizedDebt * ilkRate;
        }
        require(totalDebt + ionPool.totalUnbackedDebt() == ionPool.debt());
    }
}
