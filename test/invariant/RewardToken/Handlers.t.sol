// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WadRayMath } from "../../../src/libraries/math/WadRayMath.sol";

import { RewardTokenExposed } from "../../helpers/RewardTokenSharedSetup.sol";
import { ERC20PresetMinterPauser } from "../../helpers/ERC20PresetMinterPauser.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

abstract contract Handler is CommonBase, StdCheats, StdUtils {
    RewardTokenExposed public immutable REWARD_MODULE;
    ERC20PresetMinterPauser public immutable UNDERLYING;

    constructor(RewardTokenExposed _rewardModule, ERC20PresetMinterPauser _underlying) {
        REWARD_MODULE = _rewardModule;
        UNDERLYING = _underlying;
    }
}

contract UserHandler is Handler {
    using WadRayMath for uint256;

    constructor(
        RewardTokenExposed _rewardModule,
        ERC20PresetMinterPauser _underlying
    )
        Handler(RewardTokenExposed(_rewardModule), _underlying)
    { }

    function mint(address account, uint256 amount) external {
        amount = bound(amount, 0, UNDERLYING.balanceOf(address(this)));
        uint256 currentSupplyFactor = REWARD_MODULE.supplyFactor();

        if (amount.rayDivDown(currentSupplyFactor) == 0) return;
        REWARD_MODULE.mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        amount = bound(amount, 0, REWARD_MODULE.getUnderlyingClaimOf(account));
        uint256 currentSupplyFactor = REWARD_MODULE.supplyFactor();

        uint256 amountNormalized = amount.rayDivUp(currentSupplyFactor);
        if (amountNormalized == 0 || amountNormalized > REWARD_MODULE.balanceOf(account)) return;
        REWARD_MODULE.burn(account, account, amount);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract SupplyFactorIncreaseHandler is Handler {
    using WadRayMath for uint256;

    constructor(
        RewardTokenExposed _REWARD_MODULE,
        ERC20PresetMinterPauser _UNDERLYING
    )
        Handler(RewardTokenExposed(_REWARD_MODULE), _UNDERLYING)
    { }

    function increaseSupplyFactor(uint256 amount) external {
        uint256 oldSupplyFactor = REWARD_MODULE.supplyFactor();
        amount = bound(amount, 1.1e27, 1.25e27); // between 1E-16 and 15%

        uint256 oldTotalSupply = REWARD_MODULE.getTotalUnderlyingClaims();
        uint256 newSupplyFactor = oldSupplyFactor.rayMulDown(amount);
        REWARD_MODULE.setSupplyFactor(newSupplyFactor);

        uint256 interestCreated = REWARD_MODULE.getTotalUnderlyingClaims() - oldTotalSupply;
        UNDERLYING.mint(address(REWARD_MODULE), interestCreated + 1);
    }
}
