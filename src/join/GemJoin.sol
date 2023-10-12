// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.21;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IonPool } from "../IonPool.sol";

contract GemJoin is Ownable2Step, Pausable {
    error Int256Overflow();

    using SafeERC20 for IERC20;

    IERC20 public immutable gem;
    IonPool public immutable pool;
    uint8 public immutable ilkIndex;

    constructor(IonPool _pool, IERC20 _gem, uint8 _ilkIndex, address owner) Ownable(owner) {
        gem = _gem;
        pool = _pool;
        ilkIndex = _ilkIndex;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function join(address user, uint256 amount) external whenNotPaused {
        if (int256(amount) < 0) revert Int256Overflow();

        pool.mintAndBurnGem(ilkIndex, user, int256(amount));
        gem.safeTransferFrom(msg.sender, address(this), amount);
    }

    function exit(address user, uint256 amount) external whenNotPaused {
        if (int256(amount) < 0) revert Int256Overflow();

        pool.mintAndBurnGem(ilkIndex, user, -int256(amount));
        gem.safeTransfer(msg.sender, amount);
    }
}
