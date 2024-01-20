// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RewardModule } from "../../../src/reward/RewardModule.sol";
import { WadRayMath } from "../../../src/libraries/math/WadRayMath.sol";

import { RewardModuleSharedSetup } from "../../helpers/RewardModuleSharedSetup.sol";

contract RewardModule_UnitTest is RewardModuleSharedSetup {
    using WadRayMath for uint256;

    uint256 internal constant INITIAL_UNDERYLING = 1000e18;

    function setUp() public override {
        super.setUp();
        underlying.mint(address(this), INITIAL_UNDERYLING);
    }

    function test_SetUp() external {
        assertEq(rewardModule.name(), NAME);
        assertEq(rewardModule.symbol(), SYMBOL);
        assertEq(rewardModule.decimals(), DECIMALS);
        assertEq(rewardModule.treasury(), TREASURY);

        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING);
        assertEq(underlying.balanceOf(address(rewardModule)), 0);
    }

    function test_MintRewardBasic() external {
        uint256 amountOfRewards = 100e18;

        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        vm.expectRevert(abi.encodeWithSelector(RewardModule.InvalidReceiver.selector, address(0)));
        rewardModule.mint(address(0), amountOfRewards);
        rewardModule.mint(address(this), amountOfRewards);

        assertEq(rewardModule.balanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewards);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewards);
    }

    function test_RevertWhen_MintingZeroTokens() external {
        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        vm.expectRevert(RewardModule.InvalidMintAmount.selector);
        rewardModule.mint(address(this), 0);
    }

    function test_MintNormalizedZeroToTreasury() external {
        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        // 1 wei / 2.5 RAY will be rounded down to zero
        rewardModule.setSupplyFactor(2.5e27);
        rewardModule.mintToTreasury(1 wei);
    }

    function test_BurnRewardBasic() external {
        uint256 amountOfRewards = 100e18;

        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        rewardModule.mint(address(this), amountOfRewards);

        assertEq(rewardModule.balanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewards);

        vm.expectRevert(abi.encodeWithSelector(RewardModule.InvalidSender.selector, address(0)));
        rewardModule.burn(address(0), address(this), amountOfRewards);
        rewardModule.burn(address(this), address(this), amountOfRewards);

        assertEq(rewardModule.balanceOf(address(this)), 0);
    }

    function test_MintRewardWithSupplyFactorChange() external {
        uint256 amountOfRewards = 100e18;
        uint256 supplyFactorOld = rewardModule.supplyFactor();

        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        rewardModule.mint(address(this), amountOfRewards);

        uint256 expectedNormalizedMint1 = amountOfRewards.rayDivDown(supplyFactorOld);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardModule.balanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewards);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewards);

        uint256 supplyFactorNew = 1.5e27;
        uint256 interestCreated = amountOfRewards.rayMulDown(supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardModule.setSupplyFactor(supplyFactorNew);

        rewardModule.mint(address(this), amountOfRewards);

        uint256 expectedNormalizedMint2 = amountOfRewards.rayDivDown(supplyFactorNew);
        uint256 totalDeposited = amountOfRewards * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.rayMulDown(supplyFactorNew);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardModule.balanceOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited);
        assertEq(underlying.balanceOf(address(rewardModule)), totalDeposited + interestCreated);

        uint256 supplyFactorSecondNew = 2.5e27; // 2.5
        interestCreated = amountOfRewards.rayMulDown(supplyFactorSecondNew - supplyFactorNew);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardModule.setSupplyFactor(supplyFactorSecondNew);

        vm.expectRevert(RewardModule.InvalidMintAmount.selector);
        rewardModule.mint(address(this), 1 wei);
    }

    function test_BurnRewardWithSupplyFactorChange() external {
        uint256 amountOfRewards = 100e18;
        uint256 supplyFactorOld = rewardModule.supplyFactor();

        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        rewardModule.mint(address(this), amountOfRewards);

        uint256 expectedNormalizedMint1 = amountOfRewards.rayDivDown(supplyFactorOld);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardModule.balanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewards);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewards);

        uint256 supplyFactorNew = 2.5e27; // 2.5
        uint256 interestCreated = amountOfRewards.rayMulDown(supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardModule.setSupplyFactor(supplyFactorNew);

        rewardModule.mint(address(this), amountOfRewards);

        uint256 expectedNormalizedMint2 = amountOfRewards.rayDivDown(supplyFactorNew);
        uint256 totalDeposited = amountOfRewards * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.rayMulDown(supplyFactorNew);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardModule.balanceOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited);
        assertEq(underlying.balanceOf(address(rewardModule)), totalDeposited + interestCreated);

        uint256 burnAmount = 150e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                RewardModule.InsufficientBalance.selector,
                address(this),
                totalDepositsNormalized,
                (totalValue + totalValue).rayDivDown(supplyFactorNew)
            )
        );
        rewardModule.burn(address(this), address(this), totalValue + totalValue);
        vm.expectRevert(abi.encodeWithSelector(RewardModule.InvalidSender.selector, address(0)));
        rewardModule.burn(address(0), address(this), totalDepositsNormalized);
        // vm.expectRevert(Reward.InvalidBurnAmount.selector);
        // rewardModule.burn(address(this), address(this), 1 wei);
        rewardModule.burn(address(this), address(this), burnAmount);

        assertEq(rewardModule.balanceOf(address(this)), totalValue - burnAmount);
        assertEq(rewardModule.totalSupply(), totalValue - burnAmount);
        assertEq(
            rewardModule.normalizedBalanceOf(address(this)),
            totalDepositsNormalized - burnAmount.rayDivDown(supplyFactorNew)
        );
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited + burnAmount);
        assertEq(underlying.balanceOf(address(rewardModule)), totalDeposited + interestCreated - burnAmount);
    }
}
