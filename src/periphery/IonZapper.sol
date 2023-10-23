// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../IonPool.sol";
import { IWETH9 } from "../interfaces/IWETH9.sol";

contract IonZapper {
    IonPool immutable ionPool;
    IWETH9 immutable weth;

    constructor(IonPool _ionPool, IWETH9 _weth) {
        ionPool = _ionPool;
        weth = _weth;
        _weth.approve(address(ionPool), type(uint256).max);
    }

    function zap() public payable {
        uint256 amount = msg.value;

        weth.deposit{ value: amount }();
        ionPool.supply(msg.sender, amount);
    }

    receive() external payable {
        zap();
    }
}
