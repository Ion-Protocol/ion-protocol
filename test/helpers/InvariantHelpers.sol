// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";

library InvariantHelpers {
    using WadRayMath for *;

    /**
     * @return utilizationRate in RAD
     */
    function getUtilizationRate(IonPool ionPool) internal view returns (uint256 utilizationRate) {
        utilizationRate = ionPool.debt().radDivDown(ionPool.normalizedTotalSupply() * ionPool.supplyFactor());
    }

    /**
     * @return utilizationRate (ilk-specific) in RAY
     */
    function getIlkSpecificUtilizationRate(
        IonPool ionPool,
        uint16[] memory distributionFactors,
        uint8 ilkIndex
    )
        internal
        view
        returns (uint256 utilizationRate)
    {
        utilizationRate =
        // Prevent division by 0
        ionPool.totalSupply() == 0
            ? 0
            : (ionPool.totalNormalizedDebt(ilkIndex) * ionPool.rate(ilkIndex))
                / (ionPool.totalSupply().wadMulDown(distributionFactors[ilkIndex].scaleUpToWad(4)));
    }
}
