// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RewardModuleExposed } from "../../helpers/RewardModuleSharedSetup.sol";
import { RoundedMath } from "../../../src/libraries/math/RoundedMath.sol";
import { ERC20PresetMinterPauser } from "../../helpers/ERC20PresetMinterPauser.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

abstract contract Handler is CommonBase, StdCheats, StdUtils {
    RewardModuleExposed public immutable rewardModule;
    ERC20PresetMinterPauser public immutable underlying;

    constructor(RewardModuleExposed _rewardModule, ERC20PresetMinterPauser _underlying) {
        rewardModule = _rewardModule;
        underlying = _underlying;
    }
}

contract UserHandler is Handler {
    using RoundedMath for uint256;

    constructor(
        RewardModuleExposed _rewardModule,
        ERC20PresetMinterPauser _underlying
    )
        Handler(RewardModuleExposed(_rewardModule), _underlying)
    { }

    function mint(address account, uint256 amount) external {
        amount = bound(amount, 0, underlying.balanceOf(address(this)));
        uint256 currentSupplyFactor = rewardModule.supplyFactor();

        if (amount.rayDivDown(currentSupplyFactor) == 0) return;
        rewardModule.mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        amount = bound(amount, 0, rewardModule.balanceOf(account));
        uint256 currentSupplyFactor = rewardModule.supplyFactor();

        uint256 amountNormalized = amount.rayDivUp(currentSupplyFactor);
        if (amountNormalized == 0 || amountNormalized > rewardModule.normalizedBalanceOf(account)) return;
        rewardModule.burn(account, account, amount);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract SupplyFactorIncreaseHandler is Handler {
    using RoundedMath for uint256;

    constructor(
        RewardModuleExposed _rewardModule,
        ERC20PresetMinterPauser _underlying
    )
        Handler(RewardModuleExposed(_rewardModule), _underlying)
    { }

    function increaseSupplyFactor(uint256 amount) external {
        uint256 oldSupplyFactor = rewardModule.supplyFactor();
        amount = bound(amount, 1.1e27, 1.25e27); // between 1E-16 and 15%

        uint256 oldTotalSupply = rewardModule.totalSupply();
        uint256 newSupplyFactor = oldSupplyFactor.rayMulDown(amount);
        rewardModule.setSupplyFactor(newSupplyFactor);

        uint256 interestCreated = rewardModule.totalSupply() - oldTotalSupply;
        underlying.mint(address(rewardModule), interestCreated + 1);
    }
}
