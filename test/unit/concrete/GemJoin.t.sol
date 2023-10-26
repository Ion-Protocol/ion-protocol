// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { GemJoin } from "src/join/GemJoin.sol";

import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";
import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract GemJoin_Test is IonPoolSharedSetup {

    address immutable NON_OWNER = vm.addr(12409204);

    function test_Pause() external {
        for (uint256 i = 0; i < gemJoins.length; i++) {
            assertEq(gemJoins[i].paused(), false);
            gemJoins[i].pause();
            assertEq(gemJoins[i].paused(), true);
        }
    }

    function test_Unpause() external {
        for (uint256 i = 0; i < gemJoins.length; i++) {
            assertEq(gemJoins[i].paused(), false);
            gemJoins[i].pause();
            assertEq(gemJoins[i].paused(), true);
        } 

        for (uint256 i = 0; i <gemJoins.length; i++) {
            assertEq(gemJoins[i].paused(), true);
            gemJoins[i].unpause();
            assertEq(gemJoins[i].paused(), false);
        }
    }

    function test_RevertWhen_PausedByNonOwner() external {
        for (uint256 i = 0; i < gemJoins.length; i++) {
            assertEq(gemJoins[i].paused(), false);

            vm.prank(NON_OWNER);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
            gemJoins[i].pause();
        }
    }

    function test_RevertWhen_UnpausedByNonOwner() external {
        for (uint256 i = 0; i < gemJoins.length; i++) {
            assertEq(gemJoins[i].paused(), false);
            gemJoins[i].pause();
            assertEq(gemJoins[i].paused(), true);

            vm.prank(NON_OWNER);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NON_OWNER));
            gemJoins[i].unpause();
        }
    }

    function test_Join() public {
        uint256 amountToJoin = 7e18;

        for (uint8 i = 0; i < gemJoins.length; i++) {
            mintableCollaterals[i].mint(address(this), amountToJoin);
            
            assertEq(ionPool.gem(i, address(this)), 0);

            IERC20 gem = gemJoins[i].gem();
            gem.approve(address(gemJoins[i]), type(uint256).max);

            gemJoins[i].join(address(this), amountToJoin);

            assertEq(ionPool.gem(i, address(this)), amountToJoin);
        }
    }

    function test_RevertWhen_JoiningOverInt256() external {
        uint256 amountToJoin = type(uint256).max;
        for (uint8 i = 0; i < gemJoins.length; i++) {
            mintableCollaterals[i].mint(address(this), amountToJoin);
            
            assertEq(ionPool.gem(i, address(this)), 0);

            IERC20 gem = gemJoins[i].gem();
            gem.approve(address(gemJoins[i]), type(uint256).max);

            vm.expectRevert(GemJoin.Int256Overflow.selector);
            gemJoins[i].join(address(this), amountToJoin);

            assertEq(ionPool.gem(i, address(this)), 0);
        } 
    }

    function test_Exit() public {
        uint256 amountToJoin = 7e18;
        uint256 amountToExit = 3e18;

        for (uint8 i = 0; i < gemJoins.length; i++) {
            mintableCollaterals[i].mint(address(this), amountToJoin);
            
            assertEq(ionPool.gem(i, address(this)), 0);

            IERC20 gem = gemJoins[i].gem();
            gem.approve(address(gemJoins[i]), type(uint256).max);

            gemJoins[i].join(address(this), amountToJoin);

            assertEq(ionPool.gem(i, address(this)), amountToJoin);

            gemJoins[i].exit(address(this), amountToExit);

            assertEq(ionPool.gem(i, address(this)), amountToJoin - amountToExit);
        }
    }

    function test_RevertWhen_ExitingOverInt256() public {
        uint256 amountToJoin = 7e18;
        uint256 amountToExit = type(uint256).max;

        for (uint8 i = 0; i < gemJoins.length; i++) {
            mintableCollaterals[i].mint(address(this), amountToJoin);
            
            assertEq(ionPool.gem(i, address(this)), 0);

            IERC20 gem = gemJoins[i].gem();
            gem.approve(address(gemJoins[i]), type(uint256).max);

            gemJoins[i].join(address(this), amountToJoin);

            assertEq(ionPool.gem(i, address(this)), amountToJoin);

            vm.expectRevert(GemJoin.Int256Overflow.selector);
            gemJoins[i].exit(address(this), amountToExit);

            assertEq(ionPool.gem(i, address(this)), amountToJoin);
        }
    }
}
