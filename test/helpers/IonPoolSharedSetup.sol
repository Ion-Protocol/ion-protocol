// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { console2 } from "forge-std/console2.sol";
import { BaseTestSetup } from "../helpers/BaseTestSetup.sol";
import { IonPool } from "../../src/IonPool.sol";
import { InterestRate, IlkData } from "../../src/InterestRate.sol";
import { IApyOracle } from "../../src/interfaces/IApyOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract MockApyOracle is IApyOracle {
    uint256 APY = 3.45e6;

    function getAPY(uint256) external view returns (uint256) {
        return APY;
    }
}

// struct IlkData {
//     uint80 minimumProfitMargin; // 18 decimals
//     uint64 reserveFactor; // 18 decimals
//     uint64 optimalUtilizationRate; // 18 decimals
//     uint16 distributionFactor; // 2 decimals
// }

contract IonPoolTest is BaseTestSetup {
    IonPool ionPool;

    InterestRate interestRateModule;
    IApyOracle apyOracle;

    // --- Configs ---
    uint256 public constant globalDebtCeiling = 100e45; // [rad]

    uint64 public stEthReserveFactor = 0.1e18; 
    uint64 public swEthReserveFactor = 0.08e18;
    uint64 public ethXReserveFactor = 0.05e18;

    function setUp() public override {
        super.setUp();
        apyOracle = new MockApyOracle();

        uint80 minimumProfitMargin = 0.85e18;

        IlkData memory stEthInterestConfig = IlkData({
            minimumProfitMargin: minimumProfitMargin,
            reserveFactor: stEthReserveFactor,
            optimalUtilizationRate: 0.9e18,
            distributionFactor: 0.2e2
        });

        IlkData memory swEthInterestConfig = IlkData({
            minimumProfitMargin: minimumProfitMargin,
            reserveFactor: swEthReserveFactor,
            optimalUtilizationRate: 0.92e18,
            distributionFactor: 0.4e2
        });

        IlkData memory ethXInterestConfig = IlkData({
            minimumProfitMargin: minimumProfitMargin,
            reserveFactor: 0.05e18,
            optimalUtilizationRate: 0.95e18,
            distributionFactor: 0.4e2
        });

        IlkData[] memory ilks = new IlkData[](3);
        ilks[0] = stEthInterestConfig;
        ilks[1] = swEthInterestConfig;
        ilks[2] = ethXInterestConfig;

        interestRateModule = new InterestRate(ilks, apyOracle);

        ionPool = new IonPool(address(underlying), TREASURY, DECIMALS, NAME, SYMBOL, address(this), interestRateModule);

        IonPool.Ilk memory stEthPoolConfig = IonPool.Ilk({
            totalNormalizedDebt: 0, // ignored
            lastRateUpdate: 0,  // ignored
            rate: 0, // ignored
            spot: 0, // [ray]
            debtCeiling: 100e45, // [rad]
            dust: 0 // [rad]
        });
    }

    function test_setUp() external {
        assertEq(address(ionPool.underlying()), address(underlying));
        assertEq(ionPool.treasury(), TREASURY);
        assertEq(ionPool.decimals(), DECIMALS);
        assertEq(ionPool.name(), NAME);
        assertEq(ionPool.symbol(), SYMBOL);
        assertEq(ionPool.defaultAdmin(), address(this));
        // assertEq(ionPool.interestRateModule(), address(interestRateModule));
    }

    function testBasicLend() external { }
}
