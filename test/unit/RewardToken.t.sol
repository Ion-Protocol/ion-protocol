// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {safeconsole as console} from "forge-std/safeconsole.sol";
import {RewardTokenSharedSetup} from "../helpers/RewardTokenSharedSetup.sol";
import {RewardToken} from "../../src/token/RewardToken.sol";
import {IERC20Errors} from "../../src/token/IERC20Errors.sol";
import {RoundedMath} from "../../src/math/RoundedMath.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract RewardTokenUnitTest is RewardTokenSharedSetup {
    using RoundedMath for uint256;

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
        uint256 supplyFactorOld = rewardToken.getSupplyFactor();

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint1 = amountOfRewardTokens.roundedRayDiv(supplyFactorOld);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        uint256 supplyFactorNew = 1.5e27;
        uint256 interestCreated = _wadMul(amountOfRewardTokens, supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardToken.setSupplyFactor(supplyFactorNew);

        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint2 = amountOfRewardTokens.roundedRayDiv(supplyFactorNew);
        uint256 totalDeposited = amountOfRewardTokens * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.roundedRayMul(supplyFactorNew);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardToken.balanceOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited);
        assertEq(underlying.balanceOf(address(rewardToken)), totalDeposited + interestCreated);

        uint256 supplyFactorSecondNew = 2.5e27; // 2.5
        interestCreated = _wadMul(amountOfRewardTokens, supplyFactorSecondNew - supplyFactorNew);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardToken.setSupplyFactor(supplyFactorSecondNew);

        vm.expectRevert(RewardToken.InvalidMintAmount.selector);
        rewardToken.mint(address(this), 1 wei);
    }

    function test_burnRewardTokenWithSupplyFactorChange() external {
        uint256 amountOfRewardTokens = 100e18;
        uint256 supplyFactorOld = rewardToken.getSupplyFactor();

        underlying.approve(address(rewardToken), INITIAL_UNDERYLING);
        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint1 = amountOfRewardTokens.roundedRayDiv(supplyFactorOld);

        assertEq(rewardToken.normalizedBalanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardToken.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(rewardToken)), amountOfRewardTokens);

        uint256 supplyFactorNew = 2.5e27; // 2.5
        uint256 interestCreated = _wadMul(amountOfRewardTokens, supplyFactorNew - supplyFactorOld);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardToken.setSupplyFactor(supplyFactorNew);

        rewardToken.mint(address(this), amountOfRewardTokens);

        uint256 expectedNormalizedMint2 = amountOfRewardTokens.roundedRayDiv(supplyFactorNew);
        uint256 totalDeposited = amountOfRewardTokens * 2;
        uint256 totalDepositsNormalized = expectedNormalizedMint1 + expectedNormalizedMint2;
        uint256 totalValue = totalDepositsNormalized.roundedRayMul(supplyFactorNew);

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
                (totalValue + totalValue).roundedRayDiv(supplyFactorNew)
            )
        );
        rewardToken.burn(address(this), address(this), totalValue + totalValue);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        rewardToken.burn(address(0), address(this), totalDepositsNormalized);
        vm.expectRevert(RewardToken.InvalidBurnAmount.selector);
        rewardToken.burn(address(this), address(this), 1 wei);
        rewardToken.burn(address(this), address(this), burnAmount);

        assertEq(rewardToken.balanceOf(address(this)), totalValue - burnAmount);
        assertEq(rewardToken.totalSupply(), totalValue - burnAmount);
        assertEq(
            rewardToken.normalizedBalanceOf(address(this)),
            totalDepositsNormalized - burnAmount.roundedRayDiv(supplyFactorNew)
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
            ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(sendingUserPrivateKey, ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash));

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
            ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash);

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(spenderPrivateKey, ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash));

            vm.expectRevert(abi.encodeWithSelector(RewardToken.ERC2612InvalidSigner.selector, spender, sendingUser));
            rewardToken.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);

            (v, r, s) = vm.sign(sendingUserPrivateKey, ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, structHash));
            (uint8 vMalleable, bytes32 rMalleable, bytes32 sMalleable) = _calculateMalleableSignature(v, r, s);
            console.log("vMalleable: %s", vMalleable);

            // Openzeppelin ECDSA library already prevents the use of malleable signatures, even if nonce-based replay protection wasn't included
            vm.expectRevert("ECDSA: invalid signature 's' value");
            rewardToken.permit(sendingUser, spender, amountOfRewardTokens, deadline, vMalleable, rMalleable, sMalleable);
            rewardToken.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);
        }

        assertEq(rewardToken.allowance(sendingUser, spender), amountOfRewardTokens);
    }

    // --- Helpers ---

    function _depositInterestGains(uint256 amount) internal {
        underlying.mint(address(rewardToken), amount);
    }

    function _wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b / 1e18;
    }

    function _calculateMalleableSignature(uint8 v, bytes32 r, bytes32 s)
        internal
        pure
        returns (uint8, bytes32, bytes32)
    {
        // Ensure v is within the valid range (27 or 28)
        require(v == 27 || v == 28, "Invalid v value");

        // Calculate the other s value by negating modulo the curve order n
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        uint256 otherS = n - uint256(s);

        // Calculate the other v value
        uint8 otherV = 55 - v;

        return (otherV, r, bytes32(otherS));
    }
}
