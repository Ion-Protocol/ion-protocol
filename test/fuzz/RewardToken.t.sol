// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { RewardToken } from "../../src/token/RewardToken.sol";
import { RewardTokenSharedSetup } from "../helpers/RewardTokenSharedSetup.sol";
import { RoundedMath, RAY } from "../../src/math/RoundedMath.sol";
import { IERC20Errors } from "../../src/token/IERC20Errors.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract RewardToken_FuzzUnitTest is RewardTokenSharedSetup {
    using RoundedMath for uint256;

    function testFuzz_mintRewardTokenBasic(uint256 amountOfRewardTokens) external {
        vm.assume(amountOfRewardTokens != 0);
        // Prevent overflow
        vm.assume(amountOfRewardTokens < 2 ** 128);

        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardToken), amountOfRewardTokens);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        rewardToken.mint(address(0), amountOfRewardTokens);
        rewardToken.mint(address(this), amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);
    }

    function testFuzz_burnRewardTokenBasic(uint256 amountOfRewardTokens) external {
        vm.assume(amountOfRewardTokens != 0);
        // Prevent overflow
        vm.assume(amountOfRewardTokens < 2 ** 128);

        // Undo setup
        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardToken), amountOfRewardTokens);
        rewardToken.mint(address(this), amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        rewardToken.burn(address(0), address(this), amountOfRewardTokens);
        rewardToken.burn(address(this), address(this), amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(address(this)), 0);
    }

    function testFuzz_mintRewardTokenWithSupplyFactorChange(
        uint256 amountOfRewardTokens,
        uint256 supplyFactorNew
    )
        external
    {
        vm.assume(amountOfRewardTokens != 0);
        // Prevent overflow
        vm.assume(amountOfRewardTokens < 2 ** 128);
        uint256 supplyFactorOld = rewardToken.supplyFactor();
        // supplyFactor greater than 10,000 is highly unlikely
        supplyFactorNew = bound(supplyFactorNew, supplyFactorOld, 5000e27);
        vm.assume(amountOfRewardTokens.rayDivDown(supplyFactorNew) != 0);

        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardToken), type(uint256).max);
        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint1 = amountOfRewardTokens.rayDivDown(supplyFactorOld);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        uint256 interestCreated = amountOfRewardTokens.wadMulDown(supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardToken.setSupplyFactor(supplyFactorNew);

        underlying.mint(address(this), amountOfRewardTokens);
        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint2 = amountOfRewardTokens.rayDivDown(supplyFactorNew);
        uint256 totalDeposited = amountOfRewardTokens * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.rayMulDown(supplyFactorNew);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardToken.balanceOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardToken)), totalDeposited + interestCreated);
    }

    function testFuzz_burnRewardTokenWithSupplyFactorChange(
        uint256 amountOfRewardTokens,
        uint256 supplyFactorNew
    )
        external
    {
        vm.assume(amountOfRewardTokens != 0);
        // Prevent overflow
        vm.assume(amountOfRewardTokens < 2 ** 128);
        uint256 supplyFactorOld = rewardToken.supplyFactor();
        // supplyFactor greater than 5,000 is highly unlikely
        supplyFactorNew = bound(supplyFactorNew, supplyFactorOld + 1, 5000e27);
        vm.assume(amountOfRewardTokens.rayDivDown(supplyFactorNew) != 0);

        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardToken), type(uint256).max);
        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint1 = amountOfRewardTokens.rayDivDown(supplyFactorOld);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        uint256 interestCreated = amountOfRewardTokens.wadMulDown(supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardToken.setSupplyFactor(supplyFactorNew);

        underlying.mint(address(this), amountOfRewardTokens);
        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint2 = amountOfRewardTokens.rayDivDown(supplyFactorNew);
        uint256 totalDeposited = amountOfRewardTokens * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.rayMulDown(supplyFactorNew);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardToken.balanceOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardToken)), totalDeposited + interestCreated);

        uint256 burnAmount = amountOfRewardTokens;

        rewardToken.burn(address(this), address(this), burnAmount);

        assertEq(underlying.balanceOf(address(this)), burnAmount);
        assertEq(underlying.balanceOf(address(rewardToken)), totalDeposited + interestCreated - burnAmount);
    }

    function testFuzz_transfer(uint256 amountOfRewardTokens) external {
        vm.assume(amountOfRewardTokens != 0);
        vm.assume(amountOfRewardTokens < 2 ** 128);

        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardToken), amountOfRewardTokens);
        rewardToken.mint(address(this), amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), 0);
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
        assertEq(underlying.balanceOf(address(this)), 0);
    }

    function testFuzz_transferFromWithApprove(uint256 amountOfRewardTokens) external {
        vm.assume(amountOfRewardTokens != 0);
        vm.assume(amountOfRewardTokens < 2 ** 128);

        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardToken), amountOfRewardTokens);
        rewardToken.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardToken.balanceOf(receivingUser), 0);
        assertEq(rewardToken.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), 0);
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

    function testFuzz_transferFromWithPermit(uint256 amountOfRewardTokens) external {
        vm.assume(amountOfRewardTokens != 0);
        vm.assume(amountOfRewardTokens < 2 ** 128);

        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardToken), amountOfRewardTokens);
        rewardToken.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardToken.balanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardToken.balanceOf(receivingUser), 0);
        assertEq(rewardToken.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), 0);
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

    struct PermitLocals {
        uint256 amountOfRewardTokens;
    }

    function testFuzz_permit(
        uint256 amountOfRewardTokens,
        uint256 nonSenderPrivateKey,
        uint256 deadlineTime
    )
        external
    {
        vm.assume(amountOfRewardTokens != 0);
        vm.assume(amountOfRewardTokens < 2 ** 128);
        nonSenderPrivateKey = bound(nonSenderPrivateKey, 100, 2 ** 128);
        deadlineTime = bound(deadlineTime, 1, 2 ** 128);

        PermitLocals memory locals = PermitLocals({ amountOfRewardTokens: amountOfRewardTokens });
        locals.amountOfRewardTokens = amountOfRewardTokens;

        underlying.mint(address(this), locals.amountOfRewardTokens);

        underlying.approve(address(rewardToken), locals.amountOfRewardTokens);
        rewardToken.mint(sendingUser, locals.amountOfRewardTokens);
        assertEq(rewardToken.balanceOf(sendingUser), locals.amountOfRewardTokens);
        assertEq(rewardToken.balanceOf(receivingUser), 0);
        assertEq(rewardToken.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardToken)), locals.amountOfRewardTokens);

        {
            bytes32 PERMIT_TYPEHASH = rewardToken.PERMIT_TYPEHASH();
            bytes32 DOMAIN_SEPARATOR = rewardToken.DOMAIN_SEPARATOR();

            uint256 deadline = block.timestamp + 30 minutes;

            // Have spender try to sign on behalf of sendingUser (should fail)
            bytes32 structHash =
                keccak256(abi.encode(PERMIT_TYPEHASH, sendingUser, spender, locals.amountOfRewardTokens, 0, deadline));
            MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(nonSenderPrivateKey, MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash));

            vm.expectRevert(
                abi.encodeWithSelector(
                    RewardToken.ERC2612InvalidSigner.selector, vm.addr(nonSenderPrivateKey), sendingUser
                )
            );
            rewardToken.permit(sendingUser, spender, locals.amountOfRewardTokens, deadline, v, r, s);

            (v, r, s) = vm.sign(sendingUserPrivateKey, MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash));
            (uint8 vMalleable, bytes32 rMalleable, bytes32 sMalleable) = _calculateMalleableSignature(v, r, s);

            // Openzeppelin ECDSA library already prevents the use of malleable signatures, even if nonce-based replay
            // protection wasn't included
            vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, sMalleable));
            rewardToken.permit(
                sendingUser, spender, locals.amountOfRewardTokens, deadline, vMalleable, rMalleable, sMalleable
            );

            uint256 prevBlockTimestamp = block.timestamp;
            vm.warp(deadline + 1);
            vm.expectRevert(abi.encodeWithSelector(RewardToken.ERC2612ExpiredSignature.selector, deadline));
            rewardToken.permit(sendingUser, spender, locals.amountOfRewardTokens, deadline, v, r, s);
            vm.warp(prevBlockTimestamp);
            rewardToken.permit(sendingUser, spender, locals.amountOfRewardTokens, deadline, v, r, s);
        }

        assertEq(rewardToken.allowance(sendingUser, spender), locals.amountOfRewardTokens);
    }
}
