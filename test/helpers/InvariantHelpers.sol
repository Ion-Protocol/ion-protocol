// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IIonLens } from "../../src/interfaces/IIonLens.sol";
import { IIonPool } from "../../src/interfaces/IIonPool.sol";
import { IonPool } from "../../src/IonPool.sol";
import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";

library InvariantHelpers {
    using WadRayMath for *;

    /**
     * @return utilizationRate in RAD
     */
    function getUtilizationRate(IonPool ionPool, IIonLens lens) internal view returns (uint256 utilizationRate) {
        IIonPool iIonPool = IIonPool(address(ionPool));
        utilizationRate = lens.debt(iIonPool).radDivDown(ionPool.totalSupply() * ionPool.supplyFactor());
    }

    /**
     * @return utilizationRate (ilk-specific) in RAY
     */
    function getIlkSpecificUtilizationRate(
        IonPool ionPool,
        IIonLens lens,
        uint16[] memory distributionFactors,
        uint8 ilkIndex
    )
        internal
        view
        returns (uint256 utilizationRate)
    {
        IIonPool iIonPool = IIonPool(address(ionPool));
        utilizationRate =
        // Prevent division by 0
        ionPool.totalSupply() == 0
            ? 0
            : (lens.totalNormalizedDebt(iIonPool, ilkIndex) * ionPool.rate(ilkIndex))
                / (ionPool.totalSupply().wadMulDown(distributionFactors[ilkIndex].scaleUpToWad(4)));
    }
}
