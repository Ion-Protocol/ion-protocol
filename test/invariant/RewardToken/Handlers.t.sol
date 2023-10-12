// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RewardTokenExposed } from "../../helpers/RewardTokenSharedSetup.sol";
import { RoundedMath } from "../../../src/math/RoundedMath.sol";
import { ERC20PresetMinterPauser } from "../../helpers/ERC20PresetMinterPauser.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

abstract contract Handler is CommonBase, StdCheats, StdUtils {
    RewardTokenExposed public immutable rewardToken;
    ERC20PresetMinterPauser public immutable underlying;

    constructor(RewardTokenExposed _rewardToken, ERC20PresetMinterPauser _underlying) {
        rewardToken = _rewardToken;
        underlying = _underlying;
    }
}

contract UserHandler is Handler {
    using RoundedMath for uint256;

    constructor(
        RewardTokenExposed _rewardToken,
        ERC20PresetMinterPauser _underlying
    )
        Handler(RewardTokenExposed(_rewardToken), _underlying)
    { }

    function mint(address account, uint256 amount) external {
        amount = bound(amount, 0, underlying.balanceOf(address(this)));
        uint256 currentSupplyFactor = rewardToken.getSupplyFactor();

        if (amount.roundedRayDiv(currentSupplyFactor) == 0) return;
        rewardToken.mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        amount = bound(amount, 0, rewardToken.balanceOf(account));
        uint256 currentSupplyFactor = rewardToken.getSupplyFactor();

        if (amount.roundedRayDiv(currentSupplyFactor) == 0) return;
        rewardToken.burn(account, account, amount);
    }

    function transfer(address account, address to, uint256 amount) external {
        amount = bound(amount, 0, rewardToken.balanceOf(address(account)));
        if (amount == 0) return;
        vm.prank(account);
        rewardToken.transfer(to, amount);
    }

    function approve(address account, address spender, uint256 amount) external {
        amount = bound(amount, 0, rewardToken.balanceOf(address(account)));
        if (amount == 0) return;
        vm.prank(account);
        rewardToken.approve(spender, amount);
    }

    function increaseAllowance(address account, address spender, uint256 amount) external {
        uint256 currentBalance = rewardToken.balanceOf(address(account));
        uint256 currentAllowance = rewardToken.allowance(account, spender);

        if (currentAllowance > currentBalance) return;

        amount = bound(amount, 0, currentBalance - currentAllowance);
        if (amount == 0) return;
        vm.prank(account);
        rewardToken.increaseAllowance(spender, amount);
    }

    function decreaseAllowance(address account, address spender, uint256 amount) external {
        amount = bound(amount, 0, rewardToken.allowance(account, spender));
        if (amount == 0) return;
        vm.prank(account);
        rewardToken.decreaseAllowance(spender, amount);
    }

    function transferFrom(address from, address spender, address to, uint256 amount) external {
        amount = bound(amount, 0, _min(rewardToken.allowance(from, address(spender)), rewardToken.balanceOf(from)));
        if (amount == 0) return;
        vm.prank(spender);
        rewardToken.transferFrom(from, to, amount);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract SupplyFactorIncreaseHandler is Handler {
    using RoundedMath for uint256;

    constructor(
        RewardTokenExposed _rewardToken,
        ERC20PresetMinterPauser _underlying
    )
        Handler(RewardTokenExposed(_rewardToken), _underlying)
    { }

    function increaseSupplyFactor(uint256 amount) external {
        uint256 oldSupplyFactor = rewardToken.getSupplyFactor();
        amount = bound(amount, 1.1e27, 1.25e27); // between 1E-16 and 15%

        uint256 oldTotalSupply = rewardToken.totalSupply();
        uint256 newSupplyFactor = oldSupplyFactor.roundedRayMul(amount);
        rewardToken.setSupplyFactor(newSupplyFactor);

        uint256 interestCreated = rewardToken.totalSupply() - oldTotalSupply;
        underlying.mint(address(rewardToken), interestCreated + 1);
    }
}
