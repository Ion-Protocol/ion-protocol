// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { BaseTestSetup } from "../helpers/BaseTestSetup.sol";
import { IonPool } from "../../src/IonPool.sol";
import { IonHandler } from "../../src/periphery/IonHandler.sol";
import { InterestRate, IlkData } from "../../src/InterestRate.sol";
import { IApyOracle } from "../../src/interfaces/IApyOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ERC20PresetMinterPauser } from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { RAY } from "../../src/math/RoundedMath.sol";

// struct IlkData {
//     uint80 minimumProfitMargin; // 18 decimals
//     uint64 reserveFactor; // 18 decimals
//     uint64 optimalUtilizationRate; // 18 decimals
//     uint16 distributionFactor; // 2 decimals
// }

contract MockApyOracle is IApyOracle {
    uint32 APY = 3.45e6;

    function apys(uint256) external view returns (uint32) {
        return APY;
    }
}

contract InterestRateExposed is InterestRate {
    constructor(IlkData[] memory ilks, IApyOracle apyOracle) InterestRate(ilks, apyOracle) { }

    function unpackCollateralConfig(uint256 index) external view returns (IlkData memory ilkData) {
        return _unpackCollateralConfig(index);
    }
}

abstract contract IonPoolSharedSetup is BaseTestSetup {
    IonPool ionPool;

    InterestRateExposed interestRateModule;
    IApyOracle apyOracle;

    mapping(address ilkAddress => uint8 ilkIndex) public ilkIndexes;

    address immutable lender1 = vm.addr(1);
    address immutable lender2 = vm.addr(2);
    address immutable borrower1 = vm.addr(3);
    address immutable borrower2 = vm.addr(4);

    // --- Configs ---
    uint256 public globalDebtCeiling = 100e45; // [rad]

    uint256 internal constant SPOT = 1e27; // [ray]
    uint80 internal constant minimumProfitMargin = 0.85e18;

    uint256 internal constant INITIAL_LENDER_UNDERLYING_BALANCE = 100e18;
    uint256 internal constant INITIAL_BORROWER_UNDERLYING_BALANCE = 100e18;

    ERC20PresetMinterPauser immutable stEth = new ERC20PresetMinterPauser("Staked Ether", "stETH");
    ERC20PresetMinterPauser immutable swEth = new ERC20PresetMinterPauser("Swell Ether", "swETH");
    ERC20PresetMinterPauser immutable ethX = new ERC20PresetMinterPauser("Ether X", "ETHX");

    uint64 internal constant stEthReserveFactor = 0.1e18;
    uint64 internal constant swEthReserveFactor = 0.08e18;
    uint64 internal constant ethXReserveFactor = 0.05e18;

    uint64 internal constant stEthOptimalUtilizationRate = 0.9e18;
    uint64 internal constant swEthOptimalUtilizationRate = 0.92e18;
    uint64 internal constant ethXOptimalUtilizationRate = 0.95e18;

    uint16 internal stEthDistributionFactor = 0.2e2;
    uint16 internal swEthDistributionFactor = 0.4e2;
    uint16 internal ethXDistributionFactor = 0.4e2;

    uint256 internal stEthDebtCeiling = 20e45;
    uint256 internal swEthDebtCeiling = 40e45;
    uint256 internal ethXDebtCeiling = 40e45;

    ERC20PresetMinterPauser[] internal collaterals;
    GemJoin[] internal gemJoins;
    uint64[] internal reserveFactors = [stEthReserveFactor, swEthReserveFactor, ethXReserveFactor];
    uint64[] internal optimalUtilizationRates =
        [stEthOptimalUtilizationRate, swEthOptimalUtilizationRate, ethXOptimalUtilizationRate];
    uint16[] internal distributionFactors = [stEthDistributionFactor, swEthDistributionFactor, ethXDistributionFactor];
    uint256[] internal debtCeilings = [stEthDebtCeiling, swEthDebtCeiling, ethXDebtCeiling];

    function setUp() public virtual override {
        collaterals = [stEth, swEth, ethX];
        assert(
            collaterals.length == reserveFactors.length && reserveFactors.length == optimalUtilizationRates.length
                && optimalUtilizationRates.length == distributionFactors.length
                && distributionFactors.length == debtCeilings.length
        );
        super.setUp();
        apyOracle = new MockApyOracle();

        IlkData[] memory ilks = new IlkData[](collaterals.length);

        uint256 distributionFactorSum;
        uint256 debtCeilingSum;

        IlkData memory ilkConfig;
        for (uint256 i = 0; i < ilks.length; i++) {
            ilkConfig = IlkData({
                minimumProfitMargin: minimumProfitMargin,
                reserveFactor: reserveFactors[i],
                optimalUtilizationRate: optimalUtilizationRates[i],
                distributionFactor: distributionFactors[i]
            });
            ilks[i] = ilkConfig;

            distributionFactorSum += distributionFactors[i];
            debtCeilingSum += debtCeilings[i];

            collaterals[i].mint(borrower1, INITIAL_BORROWER_UNDERLYING_BALANCE);
            collaterals[i].mint(borrower2, INITIAL_BORROWER_UNDERLYING_BALANCE);
        }

        assert(distributionFactorSum == 1e2);
        assert(debtCeilingSum == globalDebtCeiling);

        interestRateModule = new InterestRateExposed(ilks, apyOracle);

        ionPool = new IonPool(address(underlying), TREASURY, DECIMALS, NAME, SYMBOL, address(this), interestRateModule);
        ionPool.grantRole(ionPool.ION(), address(this));
        ionPool.updateGlobalDebtCeiling(globalDebtCeiling);

        for (uint8 i = 0; i < collaterals.length; i++) {
            ionPool.init(address(collaterals[i]));
            ionPool.updateIlkConfig(i, SPOT, debtCeilings[i], 0);
            gemJoins.push(new GemJoin(ionPool, collaterals[i], i));
            ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(gemJoins[i]));
        }

        underlying.mint(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        underlying.mint(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);
    }

    function test_setUp() external virtual {
        assertEq(address(ionPool.underlying()), address(underlying));
        assertEq(ionPool.treasury(), TREASURY);
        assertEq(ionPool.decimals(), DECIMALS);
        assertEq(ionPool.name(), NAME);
        assertEq(ionPool.symbol(), SYMBOL);
        assertEq(ionPool.defaultAdmin(), address(this));

        assertEq(ionPool.ilkCount(), collaterals.length);

        uint256 addressesLength = ionPool.addressesLength();
        assertEq(addressesLength, collaterals.length);
        for (uint8 i = 0; i < addressesLength; i++) {
            assertEq(ionPool.getIlkAddress(i), address(collaterals[i]));

            assertEq(ionPool.totalNormalizedDebt(i), 0);
            assertEq(ionPool.rate(i), 1e27);
            assertEq(ionPool.spot(i), SPOT);
            assertEq(ionPool.debtCeiling(i), debtCeilings[i]);
            assertEq(ionPool.dust(i), 0);

            assertEq(ionPool.collateral(i, lender1), 0);
            assertEq(ionPool.collateral(i, lender2), 0);
            assertEq(ionPool.collateral(i, borrower1), 0);
            assertEq(ionPool.collateral(i, borrower2), 0);
            assertEq(ionPool.normalizedDebt(i, lender1), 0);
            assertEq(ionPool.normalizedDebt(i, lender2), 0);
            assertEq(ionPool.normalizedDebt(i, borrower1), 0);
            assertEq(ionPool.normalizedDebt(i, borrower2), 0);

            (uint256 borrowRate, uint256 reserveFactor) = ionPool.getCurrentBorrowRate(i);
            assertEq(borrowRate, 1 * RAY);
            assertEq(reserveFactor, reserveFactors[i]);

            assertEq(collaterals[i].balanceOf(address(ionPool)), 0);
            assertEq(collaterals[i].balanceOf(address(borrower1)), INITIAL_BORROWER_UNDERLYING_BALANCE);
            assertEq(collaterals[i].balanceOf(address(borrower2)), INITIAL_BORROWER_UNDERLYING_BALANCE);

            IlkData memory ilkConfig = interestRateModule.unpackCollateralConfig(i);
            assertEq(ilkConfig.minimumProfitMargin, minimumProfitMargin);
            assertEq(ilkConfig.reserveFactor, reserveFactors[i]);
            assertEq(ilkConfig.optimalUtilizationRate, optimalUtilizationRates[i]);
            assertEq(ilkConfig.distributionFactor, distributionFactors[i]);
        }

        assertEq(interestRateModule.collateralCount(), collaterals.length);
    }
}
