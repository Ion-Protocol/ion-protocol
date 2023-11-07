// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RewardModule } from "src/reward/RewardModule.sol";
import { RoundedMath, RAY } from "src/libraries/math/RoundedMath.sol";

import { RewardModuleSharedSetup } from "test/helpers/RewardModuleSharedSetup.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

contract RewardModule_FuzzUnitTest is RewardModuleSharedSetup {
    using RoundedMath for uint256;

    function testFuzz_MintRewardBasic(uint256 amountOfRewards) external {
        vm.assume(amountOfRewards != 0);
        // Prevent overflow
        vm.assume(amountOfRewards < 2 ** 128);

        underlying.mint(address(this), amountOfRewards);

        underlying.approve(address(rewardModule), amountOfRewards);
        vm.expectRevert(abi.encodeWithSelector(RewardModule.InvalidReceiver.selector, address(0)));
        rewardModule.mint(address(0), amountOfRewards);
        rewardModule.mint(address(this), amountOfRewards);

        assertEq(rewardModule.balanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewards);
    }

    function testFuzz_BurnRewardBasic(uint256 amountOfRewards) external {
        vm.assume(amountOfRewards != 0);
        // Prevent overflow
        vm.assume(amountOfRewards < 2 ** 128);

        // Undo setup
        underlying.mint(address(this), amountOfRewards);

        underlying.approve(address(rewardModule), amountOfRewards);
        rewardModule.mint(address(this), amountOfRewards);

        assertEq(rewardModule.balanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), 0);

        vm.expectRevert(abi.encodeWithSelector(RewardModule.InvalidSender.selector, address(0)));
        rewardModule.burn(address(0), address(this), amountOfRewards);
        rewardModule.burn(address(this), address(this), amountOfRewards);

        assertEq(rewardModule.balanceOf(address(this)), 0);
    }

    function testFuzz_MintRewardWithSupplyFactorChange(uint256 amountOfRewards, uint256 supplyFactorNew) external {
        vm.assume(amountOfRewards != 0);
        // Prevent overflow
        vm.assume(amountOfRewards < 2 ** 128);
        uint256 supplyFactorOld = rewardModule.supplyFactor();
        // supplyFactor greater than 10,000 is highly unlikely
        supplyFactorNew = bound(supplyFactorNew, supplyFactorOld, 5000e27);
        vm.assume(amountOfRewards.rayDivDown(supplyFactorNew) != 0);

        underlying.mint(address(this), amountOfRewards);

        underlying.approve(address(rewardModule), type(uint256).max);
        rewardModule.mint(address(this), amountOfRewards);

        uint256 expectedNormalizedMint1 = amountOfRewards.rayDivDown(supplyFactorOld);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardModule.balanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewards);

        uint256 interestCreated = amountOfRewards.wadMulDown(supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardModule.setSupplyFactor(supplyFactorNew);

        underlying.mint(address(this), amountOfRewards);
        rewardModule.mint(address(this), amountOfRewards);

        uint256 expectedNormalizedMint2 = amountOfRewards.rayDivDown(supplyFactorNew);
        uint256 totalDeposited = amountOfRewards * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.rayMulDown(supplyFactorNew);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardModule.balanceOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardModule)), totalDeposited + interestCreated);
    }

    function testFuzz_BurnRewardWithSupplyFactorChange(uint256 amountOfRewards, uint256 supplyFactorNew) external {
        vm.assume(amountOfRewards != 0);
        // Prevent overflow
        vm.assume(amountOfRewards < 2 ** 128);
        uint256 supplyFactorOld = rewardModule.supplyFactor();
        // supplyFactor greater than 5,000 is highly unlikely
        supplyFactorNew = bound(supplyFactorNew, supplyFactorOld + 1, 5000e27);
        vm.assume(amountOfRewards.rayDivDown(supplyFactorNew) != 0);

        underlying.mint(address(this), amountOfRewards);

        underlying.approve(address(rewardModule), type(uint256).max);
        rewardModule.mint(address(this), amountOfRewards);

        uint256 expectedNormalizedMint1 = amountOfRewards.rayDivDown(supplyFactorOld);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardModule.balanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewards);

        uint256 interestCreated = amountOfRewards.wadMulDown(supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardModule.setSupplyFactor(supplyFactorNew);

        underlying.mint(address(this), amountOfRewards);
        rewardModule.mint(address(this), amountOfRewards);

        uint256 expectedNormalizedMint2 = amountOfRewards.rayDivDown(supplyFactorNew);
        uint256 totalDeposited = amountOfRewards * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.rayMulDown(supplyFactorNew);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardModule.balanceOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardModule)), totalDeposited + interestCreated);

        uint256 burnAmount = amountOfRewards;

        rewardModule.burn(address(this), address(this), burnAmount);

        assertEq(underlying.balanceOf(address(this)), burnAmount);
        assertEq(underlying.balanceOf(address(rewardModule)), totalDeposited + interestCreated - burnAmount);
    }
}
