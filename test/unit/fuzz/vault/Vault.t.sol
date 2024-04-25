// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPoolExposed } from "../../../helpers/IonPoolSharedSetup.sol";
import { VaultSharedSetup } from "../../../helpers/VaultSharedSetup.sol";

import { WadRayMath, RAY, WAD } from "./../../../../src/libraries/math/WadRayMath.sol";

contract Vault_Fuzz is VaultSharedSetup {
    function setUp() public override {
        super.setUp();

        BASE_ASSET.approve(address(weEthIonPool), type(uint256).max);
        BASE_ASSET.approve(address(rsEthIonPool), type(uint256).max);
        BASE_ASSET.approve(address(rswEthIonPool), type(uint256).max);
    }

    /*
     * Confirm rounding error max bound
     * error = asset - floor[asset * RAY - (asset * RAY) % SF] / RAY)
     * Considering the modulos, this error value is max bounded to
     * max bound error = (SF - 2) / RAY + 1
     * NOTE: While this passes, the expression with SF - 3 also passes, so not
     * yet a guarantee that this is the tightest bound possible. 
     */
    function test_IonPoolSupplyRoundingError(uint256 assets, uint256 supplyFactor) public {
        assets = bound(assets, 1e18, type(uint128).max);
        supplyFactor = bound(supplyFactor, 1e27, assets * RAY);

        setERC20Balance(address(BASE_ASSET), address(this), assets);

        IonPoolExposed(address(weEthIonPool)).setSupplyFactor(supplyFactor);

        weEthIonPool.supply(address(this), assets, new bytes32[](0));

        uint256 expectedClaim = assets;
        uint256 resultingClaim = weEthIonPool.getUnderlyingClaimOf(address(this));

        uint256 re = assets - ((assets * RAY - ((assets * RAY) % supplyFactor)) / RAY);
        assertLe(expectedClaim - resultingClaim, (supplyFactor - WAD) / RAY + 1);
    }
}
