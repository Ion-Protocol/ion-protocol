// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { safeconsole as console } from "forge-std/safeconsole.sol";
import { RewardTokenSharedSetup } from "../../helpers/RewardTokenSharedSetup.sol";
import { UserHandler, SupplyFactorIncreaseHandler } from "./Handlers.t.sol";
import { RoundedMath } from "../../../src/math/RoundedMath.sol";

import { CommonBase } from "forge-std/Base.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { StdUtils } from "forge-std/StdUtils.sol";

contract ActorManager is CommonBase, StdCheats, StdUtils {
    UserHandler[] public userHandlers;
    SupplyFactorIncreaseHandler public supplyFactorIncreaseHandler;

    constructor(UserHandler[] memory _userHandlers, SupplyFactorIncreaseHandler _supplyFactorIncreaseHandler) {
        userHandlers = _userHandlers;
        supplyFactorIncreaseHandler = _supplyFactorIncreaseHandler;
    }

    // --- User Functions ---

    function mint(uint256 handlerIndex, uint256 amount) external {
        handlerIndex = bound(handlerIndex, 0, userHandlers.length - 1);
        UserHandler user = userHandlers[handlerIndex];

        user.mint(address(user), amount);
    }

    function burn(uint256 handlerIndex, uint256 amount) external {
        handlerIndex = bound(handlerIndex, 0, userHandlers.length - 1);
        UserHandler user = userHandlers[handlerIndex];

        user.burn(address(user), amount);
    }

    function transfer(uint256 handlerIndex, uint256 transferToIndex, uint256 amount) external {
        handlerIndex = bound(handlerIndex, 0, userHandlers.length - 1);
        transferToIndex = bound(transferToIndex, 0, userHandlers.length - 1);

        UserHandler user = userHandlers[handlerIndex];
        address transferToUser = address(_pickOther(userHandlers, handlerIndex, transferToIndex));

        user.transfer(address(user), transferToUser, amount);
    }

    function approve(uint256 handlerIndex, uint256 spenderIndex, uint256 amount) external {
        handlerIndex = bound(handlerIndex, 0, userHandlers.length - 1);
        spenderIndex = bound(spenderIndex, 0, userHandlers.length - 1);

        UserHandler user = userHandlers[handlerIndex];
        address spender = address(_pickOther(userHandlers, handlerIndex, spenderIndex));

        user.approve(address(user), spender, amount);
    }

    function increaseAllowance(uint256 handlerIndex, uint256 spenderIndex, uint256 amount) external {
        handlerIndex = bound(handlerIndex, 0, userHandlers.length - 1);
        spenderIndex = bound(spenderIndex, 0, userHandlers.length - 1);

        UserHandler user = userHandlers[handlerIndex];
        address spender = address(_pickOther(userHandlers, handlerIndex, spenderIndex));

        user.increaseAllowance(address(user), spender, amount);
    }

    function decreaseAllowance(uint256 handlerIndex, uint256 spenderIndex, uint256 amount) external {
        handlerIndex = bound(handlerIndex, 0, userHandlers.length - 1);
        spenderIndex = bound(spenderIndex, 0, userHandlers.length - 1);

        UserHandler user = userHandlers[handlerIndex];
        address spender = address(_pickOther(userHandlers, handlerIndex, spenderIndex));

        user.decreaseAllowance(address(user), spender, amount);
    }

    function transferFrom(
        uint256 handlerIndex,
        uint256 spenderIndex,
        uint256 transferToIndex,
        uint256 amount
    )
        external
    {
        handlerIndex = bound(handlerIndex, 0, userHandlers.length - 1);
        spenderIndex = bound(spenderIndex, 0, userHandlers.length - 1);
        transferToIndex = bound(transferToIndex, 0, userHandlers.length - 1);

        UserHandler user = userHandlers[handlerIndex];
        // spender and transferTo can be same
        address spender = address(_pickOther(userHandlers, handlerIndex, spenderIndex));
        address transferToUser = address(_pickOther(userHandlers, handlerIndex, transferToIndex));

        user.transferFrom(address(user), spender, transferToUser, amount);
    }

    // --- SupplyFactorIncreaser Functions ---

    function increaseSupplyFactor(uint256 amount) external {
        supplyFactorIncreaseHandler.increaseSupplyFactor(amount);
    }

    // --- Helper Functions ---

    /**
     * @dev Provides a `UserHandler` that is not the one at `handlerIndex`.
     * @param handlers a storage pointer to the handlers
     * @param handlerIndex the index of the handler to exclude (bounded)
     * @param otherIndex the index of the handler to return (bounded)
     */
    function _pickOther(
        UserHandler[] storage handlers,
        uint256 handlerIndex,
        uint256 otherIndex
    )
        internal
        view
        returns (UserHandler)
    {
        if (otherIndex != handlerIndex) return handlers[otherIndex];

        return handlers[(otherIndex + 1) % handlers.length];
    }
}

/**
 * @dev One big assumption of this invariant test is that `supplyFactor` is
 * always increased in proportion to the increase in the `RewardToken`
 * contract's underlying balance since the last time `supplyFactor` was
 * increased.
 */
contract RewardToken_InvariantTest is RewardTokenSharedSetup {
    using RoundedMath for uint256;

    ActorManager public actorManager;
    UserHandler[] public userHandlers;
    SupplyFactorIncreaseHandler public supplyFactorIncreaseHandler;

    uint256 internal constant AMOUNT_USERS = 8;
    uint256 internal constant USER_INITIAL_BALANCE = 1000e18;

    function setUp() public override {
        super.setUp();

        for (uint256 i = 0; i < AMOUNT_USERS; i++) {
            UserHandler user = new UserHandler(rewardToken, underlying);
            userHandlers.push(user);
            underlying.mint(address(user), USER_INITIAL_BALANCE);

            vm.prank(address(user));
            underlying.approve(address(rewardToken), type(uint256).max); // max approval
        }

        supplyFactorIncreaseHandler = new SupplyFactorIncreaseHandler(rewardToken, underlying);
        underlying.grantRole(underlying.MINTER_ROLE(), address(supplyFactorIncreaseHandler));

        actorManager = new ActorManager(userHandlers, supplyFactorIncreaseHandler);

        targetContract(address(actorManager));
    }

    function invariant_userBalancesAlwaysAddToTotalSupply() external {
        // Accounting must be done in normalized fashion
        uint256 totalSupplyByBalances;
        for (uint256 i = 0; i < userHandlers.length; i++) {
            UserHandler user = userHandlers[i];
            totalSupplyByBalances += rewardToken.normalizedBalanceOf(address(user));
        }

        underlying.balanceOf(address(rewardToken)); // update underlying balance
        rewardToken.totalSupply();

        assertEq(rewardToken.normalizedTotalSupply(), totalSupplyByBalances);
    }

    function invariant_totalSupplyAlwaysBacked() external {
        uint256 totalSupply = rewardToken.totalSupply();

        uint256 underlyingBalance = underlying.balanceOf(address(rewardToken));

        assertGe(underlyingBalance, totalSupply);
    }
}
