// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

contract MockIonPool {
    bool public paused;

    constructor() {
        paused = false;
    }

    function pause() external {
        paused = true;
    }

    function unpause() external {
        paused = false;
    }

    function accrueInterest() external returns (uint256) {
        // Do nothing
    }
}
