// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { IWETH9 } from "src/interfaces/IWETH9.sol";
import { Whitelist } from "src/Whitelist.sol";

contract IonZapper {
    IonPool public immutable ionPool;
    IWETH9 public immutable weth;
    Whitelist public immutable whitelist;

    modifier onlyWhitelistedLenders(bytes32[] memory proof) {
        whitelist.isWhitelistedLender(msg.sender, proof);
        _;
    }

    constructor(IonPool _ionPool, IWETH9 _weth, Whitelist _whitelist) {
        ionPool = _ionPool;
        weth = _weth;
        whitelist = _whitelist;
        _weth.approve(address(ionPool), type(uint256).max);
    }

    function zapSupply(bytes32[] calldata proof) external payable onlyWhitelistedLenders(proof) {
        uint256 amount = msg.value;

        weth.deposit{ value: amount }();
        ionPool.supply(msg.sender, amount, new bytes32[](0));
    }

    function zapDepositWstEth() external payable { }
}
