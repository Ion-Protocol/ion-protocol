// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../IonPool.sol";
import { IWETH9 } from "../interfaces/IWETH9.sol";
import { Whitelist } from "src/Whitelist.sol";

contract IonZapper {
    IonPool immutable ionPool;
    IWETH9 immutable weth;
    Whitelist immutable whitelist;

    modifier onlyWhitelistedLenders(bytes32[] memory proof) {
        whitelist.isWhitelistedLender(proof, msg.sender);
        _;
    }

    constructor(IonPool _ionPool, IWETH9 _weth, Whitelist _whitelist) {
        ionPool = _ionPool;
        weth = _weth;
        whitelist = _whitelist;
        _weth.approve(address(ionPool), type(uint256).max);
    }

    function zap(bytes32[] calldata proof) public payable onlyWhitelistedLenders(proof) {
        uint256 amount = msg.value;

        weth.deposit{ value: amount }();
        bytes32[] memory empty;
        ionPool.supply(msg.sender, amount, empty); // passes in empty proof since whitelist is checked in the modifier
    }
}
