// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { IonPool } from "../../src/IonPool.sol";

contract DeployIonPoolScript is DeployScript {
    function run() public broadcast returns (IonPool ionImpl) {
        ionImpl = new IonPool();
    }
}
