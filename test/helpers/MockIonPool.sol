// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

contract MockIonPool {
    function paused() external pure returns (bool) {
        return false;
    }

    function accrueInterest() external returns (uint256) {
        // Do nothing
    }
}
