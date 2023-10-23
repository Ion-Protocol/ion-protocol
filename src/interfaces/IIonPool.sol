// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IIonPool {
    function supply(uint256 amount) external;

    function redeem(uint256 amount) external;

    function exit(uint256 amount) external;

    function joinGem(bytes32 ilk, address usr, uint256 amt) external;

    function exitGem(bytes32 ilk, address usr, uint256 amt) external;
}
