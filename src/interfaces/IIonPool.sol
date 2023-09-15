// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IIonPool {
    function supply(uint256 amount) external;

    function redeem(uint256 amount) external;

    function exit(uint256 amount) external;

    function join(uint256 amount) external;
}
