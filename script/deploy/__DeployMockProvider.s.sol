// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";
import { MockLido, MockStader, MockSwell } from "../../test/helpers/YieldOracleSharedSetup.sol";

import { DeployScript } from "../Deploy.s.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract DeployMockProvidersScript is DeployScript {
    using WadRayMath for uint256;
    using SafeCast for uint256;
    using StdJson for string;

    function run() public broadcast {
        new MockLido();
        new MockStader();
        new MockSwell();
    }
}
