// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RewardToken } from "../../../src/token/RewardToken.sol";
import { WadRayMath } from "../../../src/libraries/math/WadRayMath.sol";
import { IERC20Errors } from "../../../src/token/IERC20Errors.sol";

import { RewardTokenSharedSetup } from "../../helpers/RewardTokenSharedSetup.sol";
import { IonPoolSharedSetup } from "../../helpers/IonPoolSharedSetup.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract RewardToken_FuzzUnitTest is RewardTokenSharedSetup {
    using WadRayMath for uint256;

    bytes private constant EIP712_REVISION = bytes("1");
    bytes32 private constant EIP712_DOMAIN =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function testFuzz_MintRewardBasic(uint256 amountOfRewards) external {
        vm.assume(amountOfRewards != 0);
        // Prevent overflow
        vm.assume(amountOfRewards < 2 ** 128);

        underlying.mint(address(this), amountOfRewards);

        underlying.approve(address(rewardModule), amountOfRewards);
        vm.expectRevert(abi.encodeWithSelector(RewardToken.InvalidReceiver.selector, address(0)));
        rewardModule.mint(address(0), amountOfRewards);
        rewardModule.mint(address(this), amountOfRewards);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), amountOfRewards);
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

        assertEq(rewardModule.normalizedBalanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), 0);

        vm.expectRevert(abi.encodeWithSelector(RewardToken.InvalidSender.selector, address(0)));
        rewardModule.burn(address(0), address(this), amountOfRewards);
        rewardModule.burn(address(this), address(this), amountOfRewards);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), 0);
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

    function testFuzz_transfer(uint256 amountOfRewardTokens) external {
        vm.assume(amountOfRewardTokens != 0);
        vm.assume(amountOfRewardTokens < 2 ** 128);

        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardModule), amountOfRewardTokens);
        rewardModule.mint(address(this), amountOfRewardTokens);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewardTokens);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                amountOfRewardTokens,
                amountOfRewardTokens + 1
            )
        );
        rewardModule.transfer(receivingUser, amountOfRewardTokens + 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        rewardModule.transfer(address(0), amountOfRewardTokens);
        vm.expectRevert(abi.encodeWithSelector(RewardToken.SelfTransfer.selector, address(this)));
        rewardModule.transfer(address(this), amountOfRewardTokens);
        rewardModule.transfer(receivingUser, amountOfRewardTokens);

        assertEq(rewardModule.normalizedBalanceOf(address(this)), 0);
        assertEq(rewardModule.normalizedBalanceOf(receivingUser), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), 0);
    }

    function testFuzz_transferFromWithApprove(uint256 amountOfRewardTokens) external {
        vm.assume(amountOfRewardTokens != 0);
        vm.assume(amountOfRewardTokens < 2 ** 128);

        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardModule), amountOfRewardTokens);
        rewardModule.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardModule.normalizedBalanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardModule.normalizedBalanceOf(receivingUser), 0);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewardTokens);

        vm.prank(sendingUser);
        rewardModule.approve(spender, amountOfRewardTokens);

        assertEq(rewardModule.allowance(sendingUser, spender), amountOfRewardTokens);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, amountOfRewardTokens
            )
        );
        rewardModule.transferFrom(sendingUser, receivingUser, amountOfRewardTokens);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                spender,
                amountOfRewardTokens,
                amountOfRewardTokens + 1
            )
        );
        vm.startPrank(spender);
        rewardModule.transferFrom(sendingUser, receivingUser, amountOfRewardTokens + 1);
        rewardModule.transferFrom(sendingUser, receivingUser, amountOfRewardTokens);

        assertEq(rewardModule.normalizedBalanceOf(sendingUser), 0);
        assertEq(rewardModule.normalizedBalanceOf(receivingUser), amountOfRewardTokens);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
    }

    function testFuzz_transferFromWithPermit(uint256 amountOfRewardTokens) external {
        vm.assume(amountOfRewardTokens != 0);
        vm.assume(amountOfRewardTokens < 2 ** 128);

        underlying.mint(address(this), amountOfRewardTokens);

        underlying.approve(address(rewardModule), amountOfRewardTokens);
        rewardModule.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardModule.normalizedBalanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardModule.normalizedBalanceOf(receivingUser), 0);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewardTokens);

        {
            bytes32 PERMIT_TYPEHASH = rewardModule.PERMIT_TYPEHASH();
            bytes32 domainSeparator = keccak256(
                abi.encode(
                    EIP712_DOMAIN,
                    keccak256(bytes(rewardModule.name())),
                    keccak256(EIP712_REVISION),
                    block.chainid,
                    address(rewardModule)
                )
            );
            uint256 deadline = block.timestamp + 30 minutes;

            bytes32 structHash =
                keccak256(abi.encode(PERMIT_TYPEHASH, sendingUser, spender, amountOfRewardTokens, 0, deadline));
            MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(sendingUserPrivateKey, MessageHashUtils.toTypedDataHash(domainSeparator, structHash));

            rewardModule.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);
        }

        assertEq(rewardModule.allowance(sendingUser, spender), amountOfRewardTokens);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, amountOfRewardTokens
            )
        );
        rewardModule.transferFrom(sendingUser, receivingUser, amountOfRewardTokens);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                spender,
                amountOfRewardTokens,
                amountOfRewardTokens + 1
            )
        );
        vm.startPrank(spender);
        rewardModule.transferFrom(sendingUser, receivingUser, amountOfRewardTokens + 1);
        rewardModule.transferFrom(sendingUser, receivingUser, amountOfRewardTokens);

        assertEq(rewardModule.normalizedBalanceOf(sendingUser), 0);
        assertEq(rewardModule.normalizedBalanceOf(receivingUser), amountOfRewardTokens);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
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

        underlying.approve(address(rewardModule), locals.amountOfRewardTokens);
        rewardModule.mint(sendingUser, locals.amountOfRewardTokens);
        assertEq(rewardModule.normalizedBalanceOf(sendingUser), locals.amountOfRewardTokens);
        assertEq(rewardModule.normalizedBalanceOf(receivingUser), 0);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), 0);
        assertEq(underlying.balanceOf(address(rewardModule)), locals.amountOfRewardTokens);

        {
            bytes32 PERMIT_TYPEHASH = rewardModule.PERMIT_TYPEHASH();
            bytes32 domainSeparator = keccak256(
                abi.encode(
                    EIP712_DOMAIN,
                    keccak256(bytes(rewardModule.name())),
                    keccak256(EIP712_REVISION),
                    block.chainid,
                    address(rewardModule)
                )
            );
            uint256 deadline = block.timestamp + 30 minutes;

            // Have spender try to sign on behalf of sendingUser (should fail)
            bytes32 structHash =
                keccak256(abi.encode(PERMIT_TYPEHASH, sendingUser, spender, locals.amountOfRewardTokens, 0, deadline));
            MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(nonSenderPrivateKey, MessageHashUtils.toTypedDataHash(domainSeparator, structHash));

            vm.expectRevert(
                abi.encodeWithSelector(
                    RewardToken.ERC2612InvalidSigner.selector, vm.addr(nonSenderPrivateKey), sendingUser
                )
            );
            rewardModule.permit(sendingUser, spender, locals.amountOfRewardTokens, deadline, v, r, s);

            (v, r, s) = vm.sign(sendingUserPrivateKey, MessageHashUtils.toTypedDataHash(domainSeparator, structHash));
            (uint8 vMalleable, bytes32 rMalleable, bytes32 sMalleable) = _calculateMalleableSignature(v, r, s);

            // Openzeppelin ECDSA library already prevents the use of malleable signatures, even if nonce-based replay
            // protection wasn't included
            vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, sMalleable));
            rewardModule.permit(
                sendingUser, spender, locals.amountOfRewardTokens, deadline, vMalleable, rMalleable, sMalleable
            );

            uint256 prevBlockTimestamp = block.timestamp;
            vm.warp(deadline + 1);
            vm.expectRevert(abi.encodeWithSelector(RewardToken.ERC2612ExpiredSignature.selector, deadline));
            rewardModule.permit(sendingUser, spender, locals.amountOfRewardTokens, deadline, v, r, s);
            vm.warp(prevBlockTimestamp);
            rewardModule.permit(sendingUser, spender, locals.amountOfRewardTokens, deadline, v, r, s);
        }

        assertEq(rewardModule.allowance(sendingUser, spender), locals.amountOfRewardTokens);
    }
}

contract RewardToken_FuzzUnitTest_WithIonPool is IonPoolSharedSetup {
    /**
     * The transfer function should take into account the up to date supply
     * factor inclusive of the interest rate accrual.
     * The decrease in sender's `balanceOf` should be equal to the increase in the recipient`s `balanceOf`.
     * Same goes for `normalizedBalanceOf`.
     */
    function testFuzz_TransferWithSupplyFactorIncrease(
        uint256 supplyAmt,
        uint256 transferAmt,
        uint256 timeDelta
    )
        public
    {
        uint8 ilkIndex = 0;
        address recipient = makeAddr("RECIPIENT");

        ionPool.updateIlkDebtCeiling(ilkIndex, type(uint256).max);

        supplyAmt = bound(supplyAmt, 1e18, 100e18);
        timeDelta = bound(timeDelta, 1 days, 10 days);
        transferAmt = bound(transferAmt, supplyAmt / 10, supplyAmt / 2);

        uint256 collateralAmt = supplyAmt;
        uint256 borrowAmt = bound(supplyAmt, supplyAmt / 2, supplyAmt);

        deal(address(underlying), address(lender1), supplyAmt);

        vm.startPrank(lender1);
        ionPool.underlying().approve(address(ionPool), supplyAmt);
        ionPool.supply(lender1, supplyAmt, new bytes32[](0));
        vm.stopPrank();

        deal(address(collaterals[ilkIndex]), address(borrower1), collateralAmt);

        vm.startPrank(borrower1);
        collaterals[ilkIndex].approve(address(gemJoins[ilkIndex]), collateralAmt);
        gemJoins[ilkIndex].join(borrower1, collateralAmt);
        ionPool.depositCollateral(ilkIndex, borrower1, borrower1, collateralAmt, new bytes32[](0));
        ionPool.borrow(ilkIndex, borrower1, borrower1, borrowAmt, new bytes32[](0));
        vm.stopPrank();

        uint256 prevSupplyFactor = ionPool.supplyFactor();

        vm.warp(block.timestamp + timeDelta);

        uint256 newSupplyFactor = ionPool.supplyFactor();

        assertGt(newSupplyFactor, prevSupplyFactor, "supply factor must go up");

        uint256 prevBalanceOf = ionPool.balanceOf(lender1);
        uint256 prevRecipientBalanceOf = ionPool.balanceOf(recipient);

        vm.prank(lender1);
        ionPool.transfer(recipient, transferAmt);

        uint256 newBalanceOf = ionPool.balanceOf(lender1);
        uint256 newRecipientBalanceOf = ionPool.balanceOf(recipient);

        assertApproxEqAbs(
            prevBalanceOf - newBalanceOf,
            newRecipientBalanceOf - prevRecipientBalanceOf,
            ionPool.supplyFactor() / 1e27,
            "the balanceOf change must be equal within a rounding error bound"
        );
    }
}
