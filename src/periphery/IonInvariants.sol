// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IIonLens } from "../interfaces/IIonLens.sol";
import { IIonPool } from "../interfaces/IIonPool.sol";
import { WadRayMath } from "../libraries/math/WadRayMath.sol";

/**
 * @notice This contract will be deployed on mainnet and be used to check the
 * invariants of the Ion system offchain every block.
 */
contract IonInvariants {
    using WadRayMath for uint256;

    IIonLens lens;

    constructor(IIonLens _lens) {
        lens = _lens;
    }

    /**
     * @notice Liquidity in pool + debt to pool >= total supply.
     */
    function Invariant1(IIonPool ionPool) external view {
        require(
            lens.liquidity(ionPool).scaleUpToRad(18) + lens.debtUnaccrued(ionPool)
                >= ionPool.normalizedTotalSupplyUnaccrued() * ionPool.supplyFactorUnaccrued()
        );
    }

    /**
     * @notice [Sum of all (ilk total normalized debt * ilk rate)] + unbacked debt >= debt to pool.
     */
    function Invariant2(IIonPool ionPool) external view {
        uint256 totalDebt;
        for (uint8 i = 0; i < lens.ilkCount(ionPool); i++) {
            uint256 totalNormalizedDebt = lens.totalNormalizedDebt(ionPool, i);
            uint256 ilkRate = lens.rateUnaccrued(ionPool, i);
            totalDebt += totalNormalizedDebt * ilkRate;
        }
        require(totalDebt + lens.totalUnbackedDebt(ionPool) == lens.debtUnaccrued(ionPool));
    }

    /**
     * @notice Invariant1 accrued
     */
    function Invariant3(IIonPool ionPool) external view {
        require(
            lens.liquidity(ionPool).scaleUpToRad(18) + lens.debt(ionPool)
                >= ionPool.normalizedTotalSupply() * ionPool.supplyFactor()
        );
    }

    /**
     * @notice Invariant2 accrued
     */
    function Invariant4(IIonPool ionPool) external view {
        uint256 totalDebt;
        for (uint8 i = 0; i < lens.ilkCount(ionPool); i++) {
            uint256 totalNormalizedDebt = lens.totalNormalizedDebt(ionPool, i);
            uint256 ilkRate = ionPool.rate(i);
            totalDebt += totalNormalizedDebt * ilkRate;
        }
        require(totalDebt + lens.totalUnbackedDebt(ionPool) == lens.debt(ionPool));
    }
}
