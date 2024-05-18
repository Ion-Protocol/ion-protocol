// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { DeployScript } from "../Deploy.s.sol";
import { IonPool } from "../../src/IonPool.sol";
import { SpotOracle } from "../../src/oracles/spot/SpotOracle.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { stdJson as StdJson } from "forge-std/StdJson.sol";

contract SetupCollateralScript is DeployScript {
    using StdJson for string;

    string configPath = "./deployment-config/06_SetupCollateral.json";
    string config = vm.readFile(configPath);

    IonPool ionPool = IonPool(config.readAddress(".ionPool"));
    SpotOracle spotOracle = SpotOracle(config.readAddress(".spotOracle"));
    uint256 debtCeiling = config.readUint(".debtCeiling");
    uint256 dust = config.readUint(".dust");

    function run() public broadcast {
        _validateInterfaceIonPool(ionPool);
        _validateInterface(IERC20(ilkAddress));
        _validateInterface(spotOracle);

        require(debtCeiling == 0 || debtCeiling >= 1e45, "debt ceiling is nominated in RAD");
        require(dust == 0 || dust >= 1e45, "dust is nominated in RAD");

        // this deployer address needs to have the ION role.
        ionPool.initializeIlk(ilkAddress);
        ionPool.updateIlkSpot(0, spotOracle);
        ionPool.updateIlkDebtCeiling(0, debtCeiling);
        ionPool.updateIlkDust(0, dust);
    }
}
