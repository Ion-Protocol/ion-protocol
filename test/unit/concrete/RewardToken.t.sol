// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RewardToken } from "src/token/RewardToken.sol";
import { IERC20Errors } from "src/token/IERC20Errors.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";

import { RewardTokenSharedSetup } from "test/helpers/RewardTokenSharedSetup.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract RewardToken_UnitTest is RewardTokenSharedSetup {
    using RoundedMath for uint256;

    uint256 internal constant INITIAL_UNDERYLING = 1000e18;

    function setUp() public override {
        super.setUp();
        underlying.mint(address(this), INITIAL_UNDERYLING);
    }

    function test_setUp() external {
        assertEq(rewardToken.name(), NAME);
        assertEq(rewardToken.symbol(), SYMBOL);

        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING);
        assertEq(underlying.balanceOf(address(rewardToken)), 0);
    }

    function test_mintRewardTokenBasic() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        rewardToken.mint(address(0), amountOfRewardTokens);
        rewardToken.mint(address(this), amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);
    }

    function test_RevertWhen_MintingZeroTokens() external {
        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        vm.expectRevert(RewardToken.InvalidMintAmount.selector);
        rewardToken.mint(address(this), 0);
    }

    function test_MintNormalizedZeroToTreasury() external {
        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        // 1 wei / 2.5 RAY will be rounded down to zero
        rewardToken.setSupplyFactor(2.5e27);
        rewardToken.mintToTreasury(1 wei);
    }

    function test_burnRewardTokenBasic() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(address(this), amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        rewardToken.burn(address(0), address(this), amountOfRewardTokens);
        rewardToken.burn(address(this), address(this), amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(address(this)), 0);
    }

    function test_mintRewardTokenWithSupplyFactorChange() external {
        uint256 amountOfRewardTokens = 100e18;
        uint256 supplyFactorOld = rewardToken.supplyFactor();

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint1 = amountOfRewardTokens.rayDivDown(supplyFactorOld);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        uint256 supplyFactorNew = 1.5e27;
        uint256 interestCreated = amountOfRewardTokens.wadMulDown(supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardToken.setSupplyFactor(supplyFactorNew);

        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint2 = amountOfRewardTokens.rayDivDown(supplyFactorNew);
        uint256 totalDeposited = amountOfRewardTokens * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.rayMulDown(supplyFactorNew);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardToken.balanceOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited);
        assertEq(underlying.balanceOf(address(rewardToken)), totalDeposited + interestCreated);

        uint256 supplyFactorSecondNew = 2.5e27; // 2.5
        interestCreated = amountOfRewardTokens.wadMulDown(supplyFactorSecondNew - supplyFactorNew);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardToken.setSupplyFactor(supplyFactorSecondNew);

        vm.expectRevert(RewardToken.InvalidMintAmount.selector);
        rewardToken.mint(address(this), 1 wei);
    }

    function test_burnRewardTokenWithSupplyFactorChange() external {
        uint256 amountOfRewardTokens = 100e18;
        uint256 supplyFactorOld = rewardToken.supplyFactor();

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint1 = amountOfRewardTokens.rayDivDown(supplyFactorOld);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        uint256 supplyFactorNew = 2.5e27; // 2.5
        uint256 interestCreated = amountOfRewardTokens.wadMulDown(supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardToken.setSupplyFactor(supplyFactorNew);

        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint2 = amountOfRewardTokens.rayDivDown(supplyFactorNew);
        uint256 totalDeposited = amountOfRewardTokens * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.rayMulDown(supplyFactorNew);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardToken.balanceOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited);
        assertEq(underlying.balanceOf(address(rewardToken)), totalDeposited + interestCreated);

        uint256 burnAmount = 150e18;

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                totalDepositsNormalized,
                (totalValue + totalValue).rayDivDown(supplyFactorNew)
            )
        );
        rewardToken.burn(address(this), address(this), totalValue + totalValue);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        rewardToken.burn(address(0), address(this), totalDepositsNormalized);
        // vm.expectRevert(RewardToken.InvalidBurnAmount.selector);
        // rewardToken.burn(address(this), address(this), 1 wei);
        rewardToken.burn(address(this), address(this), burnAmount);

        assertEq(rewardToken.balanceOf(address(this)), totalValue - burnAmount);
        assertEq(rewardToken.totalSupply(), totalValue - burnAmount);
        assertEq(
            rewardToken.normalizedBalanceOf(address(this)),
            totalDepositsNormalized - burnAmount.rayDivDown(supplyFactorNew)
        );
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited + burnAmount);
        assertEq(underlying.balanceOf(address(rewardToken)), totalDeposited + interestCreated - burnAmount);
    }

    function test_transfer() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(address(this), amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                amountOfRewardTokens,
                amountOfRewardTokens + 1
            )
        );
        rewardToken.transfer(receivingUser, amountOfRewardTokens + 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        rewardToken.transfer(address(0), amountOfRewardTokens);
        vm.expectRevert(abi.encodeWithSelector(RewardToken.SelfTransfer.selector, address(this)));
        rewardToken.transfer(address(this), amountOfRewardTokens);
        rewardToken.transfer(receivingUser, amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(address(this)), 0);
        assertEq(rewardToken.balanceOf(receivingUser), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
    }

    function test_transferFromWithApprove() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardToken.balanceOf(receivingUser), 0);
        assertEq(rewardToken.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        vm.prank(sendingUser);
        rewardToken.approve(spender, amountOfRewardTokens);

        assertEq(rewardToken.allowance(sendingUser, spender), amountOfRewardTokens);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, amountOfRewardTokens
            )
        );
        rewardToken.transferFrom(sendingUser, receivingUser, amountOfRewardTokens);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                spender,
                amountOfRewardTokens,
                amountOfRewardTokens + 1
            )
        );
        vm.startPrank(spender);
        rewardToken.transferFrom(sendingUser, receivingUser, amountOfRewardTokens + 1);
        rewardToken.transferFrom(sendingUser, receivingUser, amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(sendingUser), 0);
        assertEq(rewardToken.balanceOf(receivingUser), amountOfRewardTokens);
        assertEq(rewardToken.allowance(sendingUser, spender), 0);
    }

    function test_transferFromWithPermit() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardToken.balanceOf(receivingUser), 0);
        assertEq(rewardToken.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        {
            bytes32 PERMIT_TYPEHASH = rewardToken.PERMIT_TYPEHASH();
            bytes32 DOMAIN_SEPARATOR = rewardToken.DOMAIN_SEPARATOR();

            uint256 deadline = block.timestamp + 30 minutes;

            bytes32 structHash =
                keccak256(abi.encode(PERMIT_TYPEHASH, sendingUser, spender, amountOfRewardTokens, 0, deadline));
            MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(sendingUserPrivateKey, MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash));

            rewardToken.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);
        }

        assertEq(rewardToken.allowance(sendingUser, spender), amountOfRewardTokens);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, amountOfRewardTokens
            )
        );
        rewardToken.transferFrom(sendingUser, receivingUser, amountOfRewardTokens);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                spender,
                amountOfRewardTokens,
                amountOfRewardTokens + 1
            )
        );
        vm.startPrank(spender);
        rewardToken.transferFrom(sendingUser, receivingUser, amountOfRewardTokens + 1);
        rewardToken.transferFrom(sendingUser, receivingUser, amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(sendingUser), 0);
        assertEq(rewardToken.balanceOf(receivingUser), amountOfRewardTokens);
        assertEq(rewardToken.allowance(sendingUser, spender), 0);
    }

    function test_permit() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardToken.balanceOf(receivingUser), 0);
        assertEq(rewardToken.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        {
            bytes32 PERMIT_TYPEHASH = rewardToken.PERMIT_TYPEHASH();
            bytes32 DOMAIN_SEPARATOR = rewardToken.DOMAIN_SEPARATOR();

            uint256 deadline = block.timestamp + 30 minutes;

            // Have spender try to sign on behalf of sendingUser (should fail)
            bytes32 structHash =
                keccak256(abi.encode(PERMIT_TYPEHASH, sendingUser, spender, amountOfRewardTokens, 0, deadline));
            MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(spenderPrivateKey, MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash));

            vm.expectRevert(abi.encodeWithSelector(RewardToken.ERC2612InvalidSigner.selector, spender, sendingUser));
            rewardToken.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);

            (v, r, s) = vm.sign(sendingUserPrivateKey, MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash));
            (uint8 vMalleable, bytes32 rMalleable, bytes32 sMalleable) = _calculateMalleableSignature(v, r, s);

            // Openzeppelin ECDSA library already prevents the use of malleable signatures, even if nonce-based replay
            // protection wasn't included
            vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, sMalleable));
            rewardToken.permit(sendingUser, spender, amountOfRewardTokens, deadline, vMalleable, rMalleable, sMalleable);

            uint256 prevBlockTimestamp = block.timestamp;
            vm.warp(deadline + 1);
            vm.expectRevert(abi.encodeWithSelector(RewardToken.ERC2612ExpiredSignature.selector, deadline));
            rewardToken.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);
            vm.warp(prevBlockTimestamp);
            rewardToken.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);
        }

        assertEq(rewardToken.allowance(sendingUser, spender), amountOfRewardTokens);
    }

    function test_increaseAllowance() external {
        uint256 amountToApproveTotal = 100e18;

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(sendingUser, amountToApproveTotal);

        assertEq(rewardToken.balanceOf(sendingUser), amountToApproveTotal);
        assertEq(rewardToken.balanceOf(receivingUser), 0);
        assertEq(rewardToken.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountToApproveTotal);
        assertEq(underlying.balanceOf(address(rewardToken)), amountToApproveTotal);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        rewardToken.increaseAllowance(address(0), amountToApproveTotal);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        rewardToken.increaseAllowance(spender, amountToApproveTotal);

        uint256 amountToApprove1 = 25e18;
        uint256 amountToApprove2 = amountToApproveTotal - amountToApprove1;

        vm.prank(sendingUser);
        rewardToken.increaseAllowance(spender, amountToApprove1);

        assertEq(rewardToken.allowance(sendingUser, spender), amountToApprove1);

        vm.prank(sendingUser);
        rewardToken.increaseAllowance(spender, amountToApprove2);

        assertEq(rewardToken.allowance(sendingUser, spender), amountToApproveTotal);
    }

    function test_decreaseAllowance() external {
        uint256 amountToApproveTotal = 100e18;

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(sendingUser, amountToApproveTotal);
        vm.prank(sendingUser);
        rewardToken.approve(spender, amountToApproveTotal);

        assertEq(rewardToken.balanceOf(sendingUser), amountToApproveTotal);
        assertEq(rewardToken.balanceOf(receivingUser), 0);
        assertEq(rewardToken.allowance(sendingUser, spender), amountToApproveTotal);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountToApproveTotal);
        assertEq(underlying.balanceOf(address(rewardToken)), amountToApproveTotal);

        address unapprovedSpender = address(14);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, unapprovedSpender, uint256(0), amountToApproveTotal
            )
        );
        rewardToken.decreaseAllowance(unapprovedSpender, amountToApproveTotal);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(0), uint256(0), amountToApproveTotal
            )
        );
        rewardToken.decreaseAllowance(address(0), amountToApproveTotal);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, uint256(0), amountToApproveTotal
            )
        );
        vm.prank(address(0));
        rewardToken.decreaseAllowance(spender, amountToApproveTotal);

        uint256 amountToDecreaseApprove1 = 25e18;
        uint256 amountToDecreaseApprove2 = amountToApproveTotal - amountToDecreaseApprove1;

        vm.prank(sendingUser);
        rewardToken.decreaseAllowance(spender, amountToDecreaseApprove1);

        assertEq(rewardToken.allowance(sendingUser, spender), amountToApproveTotal - amountToDecreaseApprove1);

        vm.prank(sendingUser);
        rewardToken.decreaseAllowance(spender, amountToDecreaseApprove2);

        assertEq(rewardToken.allowance(sendingUser, spender), 0);
    }
}
