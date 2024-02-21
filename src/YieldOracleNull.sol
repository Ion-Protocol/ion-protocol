// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IYieldOracle } from "./interfaces/IYieldOracle.sol";

contract YieldOracleNull is IYieldOracle {
    function apys(uint256) external pure returns (uint32) {
        return 0;
    } 
}
