// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RewardToken } from "../../../src/token/RewardToken.sol";
import { IERC20Errors } from "../../../src/token/IERC20Errors.sol";
import { WadRayMath } from "../../../src/libraries/math/WadRayMath.sol";

import { RewardTokenSharedSetup } from "../../helpers/RewardTokenSharedSetup.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract RewardToken_UnitTest is RewardTokenSharedSetup {
    using WadRayMath for uint256;

    uint256 internal constant INITIAL_UNDERYLING = 1000e18;

    bytes private constant EIP712_REVISION = bytes("1");
    bytes32 private constant EIP712_DOMAIN =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

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
        vm.expectRevert(abi.encodeWithSelector(RewardToken.InvalidReceiver.selector, address(0)));
        rewardModule.mint(address(0), amountOfRewards);
        rewardModule.mint(address(this), amountOfRewards);

        assertEq(rewardModule.balanceOf(address(this)), amountOfRewards);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewards);
        assertEq(underlying.balanceOf(address(rewardModule)), amountOfRewards);
    }

    function test_RevertWhen_MintingZeroTokens() external {
        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        vm.expectRevert(RewardToken.InvalidMintAmount.selector);
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

        vm.expectRevert(abi.encodeWithSelector(RewardToken.InvalidSender.selector, address(0)));
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

        assertEq(rewardModule.balanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardModule.getUnderlyingClaimOf(address(this)), amountOfRewards);
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

        assertEq(rewardModule.balanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardModule.getUnderlyingClaimOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited);
        assertEq(underlying.balanceOf(address(rewardModule)), totalDeposited + interestCreated);

        uint256 supplyFactorSecondNew = 2.5e27; // 2.5
        interestCreated = amountOfRewards.rayMulDown(supplyFactorSecondNew - supplyFactorNew);
        // Adds amount of underlying to the reward token contract based on how
        // much the supply factor was changed
        _depositInterestGains(interestCreated);
        rewardModule.setSupplyFactor(supplyFactorSecondNew);

        vm.expectRevert(RewardToken.InvalidMintAmount.selector);
        rewardModule.mint(address(this), 1 wei);
    }

    function test_BurnRewardWithSupplyFactorChange() external {
        uint256 amountOfRewards = 100e18;
        uint256 supplyFactorOld = rewardModule.supplyFactor();

        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        rewardModule.mint(address(this), amountOfRewards);

        uint256 expectedNormalizedMint1 = amountOfRewards.rayDivDown(supplyFactorOld);

        assertEq(rewardModule.balanceOf(address(this)), expectedNormalizedMint1);
        assertEq(rewardModule.getUnderlyingClaimOf(address(this)), amountOfRewards);
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

        assertEq(rewardModule.balanceOf(address(this)), totalDepositsNormalized);
        assertEq(rewardModule.getUnderlyingClaimOf(address(this)), totalValue);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited);
        assertEq(underlying.balanceOf(address(rewardModule)), totalDeposited + interestCreated);

        uint256 burnAmount = 150e18;
        uint256 burnAmountNormalized = burnAmount.rayDivUp(supplyFactorNew);

        vm.expectRevert(
            abi.encodeWithSelector(
                RewardToken.InsufficientBalance.selector,
                address(this),
                totalDepositsNormalized,
                (totalValue + totalValue).rayDivDown(supplyFactorNew)
            )
        );
        rewardModule.burn(address(this), address(this), totalValue + totalValue);
        vm.expectRevert(abi.encodeWithSelector(RewardToken.InvalidSender.selector, address(0)));
        rewardModule.burn(address(0), address(this), totalValue);

        vm.expectRevert(RewardToken.InvalidBurnAmount.selector);
        rewardModule.burn(address(this), address(this), 0 wei); // only 0 wei will revert with InvalidBurnAmount since
            // RewardToken rounds up burn amount in protocol favor

        rewardModule.burn(address(this), address(this), burnAmount);

        assertEq(rewardModule.getUnderlyingClaimOf(address(this)), totalValue - burnAmount);
        assertEq(rewardModule.totalSupply(), totalDepositsNormalized - burnAmountNormalized, "total supply after burn");
        assertEq(rewardModule.balanceOf(address(this)), totalDepositsNormalized - burnAmountNormalized);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - totalDeposited + burnAmount);
        assertEq(underlying.balanceOf(address(rewardModule)), totalDeposited + interestCreated - burnAmount);
    }

    function test_transfer() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        rewardModule.mint(address(this), amountOfRewardTokens);

        assertEq(rewardModule.balanceOf(address(this)), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
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

        assertEq(rewardModule.balanceOf(address(this)), 0);
        assertEq(rewardModule.balanceOf(receivingUser), amountOfRewardTokens);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
    }

    function test_transferFromWithApprove() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        rewardModule.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardModule.balanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardModule.balanceOf(receivingUser), 0);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
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

        assertEq(rewardModule.balanceOf(sendingUser), 0);
        assertEq(rewardModule.balanceOf(receivingUser), amountOfRewardTokens);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
    }

    function test_transferFromWithPermit() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        rewardModule.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardModule.balanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardModule.balanceOf(receivingUser), 0);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
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

        assertEq(rewardModule.balanceOf(sendingUser), 0);
        assertEq(rewardModule.balanceOf(receivingUser), amountOfRewardTokens);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
    }

    function test_permit() external {
        uint256 amountOfRewardTokens = 100e18;

        underlying.approve(address(rewardModule), INITIAL_UNDERYLING);
        rewardModule.mint(sendingUser, amountOfRewardTokens);

        assertEq(rewardModule.balanceOf(sendingUser), amountOfRewardTokens);
        assertEq(rewardModule.balanceOf(receivingUser), 0);
        assertEq(rewardModule.allowance(sendingUser, spender), 0);
        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING - amountOfRewardTokens);
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

            // Have spender try to sign on behalf of sendingUser (should fail)
            bytes32 structHash =
                keccak256(abi.encode(PERMIT_TYPEHASH, sendingUser, spender, amountOfRewardTokens, 0, deadline));

            (uint8 v, bytes32 r, bytes32 s) =
                vm.sign(spenderPrivateKey, MessageHashUtils.toTypedDataHash(domainSeparator, structHash));

            vm.expectRevert(abi.encodeWithSelector(RewardToken.ERC2612InvalidSigner.selector, spender, sendingUser));
            rewardModule.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);

            (v, r, s) = vm.sign(sendingUserPrivateKey, MessageHashUtils.toTypedDataHash(domainSeparator, structHash));
            (uint8 vMalleable, bytes32 rMalleable, bytes32 sMalleable) = _calculateMalleableSignature(v, r, s);

            // Openzeppelin ECDSA library already prevents the use of malleable signatures, even if nonce-based replay
            // protection wasn't included
            vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, sMalleable));
            rewardModule.permit(
                sendingUser, spender, amountOfRewardTokens, deadline, vMalleable, rMalleable, sMalleable
            );

            uint256 prevBlockTimestamp = block.timestamp;
            vm.warp(deadline + 1);
            vm.expectRevert(abi.encodeWithSelector(RewardToken.ERC2612ExpiredSignature.selector, deadline));
            rewardModule.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);
            vm.warp(prevBlockTimestamp);
            rewardModule.permit(sendingUser, spender, amountOfRewardTokens, deadline, v, r, s);
        }

        assertEq(rewardModule.allowance(sendingUser, spender), amountOfRewardTokens);
    }
}
