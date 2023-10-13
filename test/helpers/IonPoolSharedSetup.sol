// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { BaseTestSetup } from "../helpers/BaseTestSetup.sol";
import { IonPool } from "../../src/IonPool.sol";
// import { IonHandler } from "../../src/periphery/IonHandler.sol";
import { InterestRate, IlkData } from "../../src/InterestRate.sol";
import { IApyOracle } from "../../src/interfaces/IApyOracle.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { ERC20PresetMinterPauser } from "../helpers/ERC20PresetMinterPauser.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { RAY } from "../../src/math/RoundedMath.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";


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

contract IonPoolExposed is IonPool {

    constructor(
        address _underlying,
        address _treasury,
        uint8 _decimals,
        string memory _name,
        string memory _symbol,
        address _defaultAdmin,
        InterestRate _interestRateModule
    ) 
    // IonPool(_underlying, _treasury, _decimals, _name, _symbol, _defaultAdmin, _interestRateModule)
    { }

    function setSupplyFactor(uint256 factor) external {
        _setSupplyFactor(factor);
    }
}

contract EmptyContract {
    function foo() public pure returns (uint256) {
        return 0;
    }
}

/*abstract*/
contract IonPoolSharedSetup is BaseTestSetup {
    IonPoolExposed ionPool;
    // IonHandler ionHandler;

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
    uint256 internal constant INITIAL_BORROWER_COLLATERAL_BALANCE = 100e18;

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

    IlkData[] ilkConfigs;

    function setUp() public virtual override {
        collaterals = [stEth, swEth, ethX];
        assert(
            collaterals.length == reserveFactors.length && reserveFactors.length == optimalUtilizationRates.length
                && optimalUtilizationRates.length == distributionFactors.length
                && distributionFactors.length == debtCeilings.length
        );
        super.setUp();
        apyOracle = new MockApyOracle();

        uint256 distributionFactorSum;
        uint256 debtCeilingSum;

        IlkData memory ilkConfig;
        for (uint256 i = 0; i < collaterals.length; i++) {
            ilkConfig = IlkData({
                minimumProfitMargin: minimumProfitMargin,
                reserveFactor: reserveFactors[i],
                optimalUtilizationRate: optimalUtilizationRates[i],
                distributionFactor: distributionFactors[i]
            });
            ilkConfigs.push(ilkConfig);

            distributionFactorSum += distributionFactors[i];
            debtCeilingSum += debtCeilings[i];

            collaterals[i].mint(borrower1, INITIAL_BORROWER_COLLATERAL_BALANCE);
            collaterals[i].mint(borrower2, INITIAL_BORROWER_COLLATERAL_BALANCE);
        }

        assert(distributionFactorSum == 1e2);
        assert(debtCeilingSum == globalDebtCeiling);

        interestRateModule = new InterestRateExposed(ilkConfigs, apyOracle);

        // Instantiate upgradeable IonPool 
        ProxyAdmin ionProxyAdmin = new ProxyAdmin(address(101));
        IonPoolExposed logicIonPool = new IonPoolExposed(address(underlying), TREASURY, DECIMALS, NAME, SYMBOL, address(this), interestRateModule);
        ionPool = IonPoolExposed(
            address(new TransparentUpgradeableProxy(address(logicIonPool), address(ionProxyAdmin), ""))
        );        
        
        ionPool.initialize(address(underlying), TREASURY, DECIMALS, NAME, SYMBOL, address(this), interestRateModule); 
        ionPool.grantRole(ionPool.ION(), address(this));
        
        // attempt to initialize again 
        vm.expectRevert(Initializable.InvalidInitialization.selector); 
        ionPool.initialize(address(underlying), TREASURY, DECIMALS, NAME, SYMBOL, address(this), interestRateModule); 

        // ionHandler = new IonHandler(ionPool);
        // vm.prank(borrower1);
        // ionPool.hope(address(ionHandler));
        // vm.prank(borrower2);
        // ionPool.hope(address(ionHandler));

        for (uint8 i = 0; i < collaterals.length; i++) {
            ionPool.initializeIlk(address(collaterals[i]));
            ionPool.updateIlkConfig(i, SPOT, debtCeilings[i], 0);
            gemJoins.push(new GemJoin(ionPool, collaterals[i], i, address(this)));
            ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(gemJoins[i]));
            ilkIndexes[address(collaterals[i])] = i;
        }

        underlying.mint(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        underlying.mint(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);
    }

    function test_setUp() public virtual {
        assertEq(address(ionPool.getUnderlying()), address(underlying));
        // assertEq(ionPool.treasury(), TREASURY);
        // assertEq(ionPool.decimals(), DECIMALS);
        // assertEq(ionPool.name(), NAME);
        // assertEq(ionPool.symbol(), SYMBOL);
        // assertEq(ionPool.defaultAdmin(), address(this));

        // assertEq(ionPool.ilkCount(), collaterals.length);

        // assertEq(ionPool.paused(), false);

        // uint256 addressesLength = ionPool.addressesLength();
        // assertEq(addressesLength, collaterals.length);
        // for (uint8 i = 0; i < addressesLength; i++) {
        //     address collateralAddress = address(collaterals[i]);
        //     assertEq(ionPool.getIlkAddress(i), collateralAddress);
        //     assertEq(ionPool.getIlkIndex(collateralAddress), ilkIndexes[collateralAddress]);

        //     assertEq(ionPool.totalNormalizedDebt(i), 0);
        //     assertEq(ionPool.rate(i), 1e27);
        //     assertEq(ionPool.spot(i), SPOT);
        //     assertEq(ionPool.debtCeiling(i), debtCeilings[i]);
        //     assertEq(ionPool.dust(i), 0);

        //     assertEq(ionPool.collateral(i, lender1), 0);
        //     assertEq(ionPool.collateral(i, lender2), 0);
        //     assertEq(ionPool.collateral(i, borrower1), 0);
        //     assertEq(ionPool.collateral(i, borrower2), 0);
        //     assertEq(ionPool.normalizedDebt(i, lender1), 0);
        //     assertEq(ionPool.normalizedDebt(i, lender2), 0);
        //     assertEq(ionPool.normalizedDebt(i, borrower1), 0);
        //     assertEq(ionPool.normalizedDebt(i, borrower2), 0);

        //     (uint256 borrowRate, uint256 reserveFactor) = ionPool.getCurrentBorrowRate(i);
        //     assertEq(borrowRate, 1 * RAY);
        //     assertEq(reserveFactor, reserveFactors[i]);

        //     assertEq(collaterals[i].balanceOf(address(ionPool)), 0);
        //     assertEq(collaterals[i].balanceOf(address(borrower1)), INITIAL_BORROWER_COLLATERAL_BALANCE);
        //     assertEq(collaterals[i].balanceOf(address(borrower2)), INITIAL_BORROWER_COLLATERAL_BALANCE);

        //     IlkData memory ilkConfig = interestRateModule.unpackCollateralConfig(i);
        //     assertEq(ilkConfig.minimumProfitMargin, minimumProfitMargin);
        //     assertEq(ilkConfig.reserveFactor, reserveFactors[i]);
        //     assertEq(ilkConfig.optimalUtilizationRate, optimalUtilizationRates[i]);
        //     assertEq(ilkConfig.distributionFactor, distributionFactors[i]);
        // }

        // assertEq(interestRateModule.collateralCount(), collaterals.length);
    }

    /**
     * @dev separated from repay for readability of tests
     * @param changeInNormalizedDebt it is expected this value will be positive
     */
    function _borrowHelper(uint8 ilkIndex, address borrower, int256 changeInNormalizedDebt) internal {
        // vm.prank(borrower);
        // ionPool.modifyPosition(ilkIndex, borrower, borrower, borrower, 0, changeInNormalizedDebt);
    }

    /**
     * @dev separated from borrow for readability of tests
     * @param changeInNormalizedDebt it is expected this value will be negative
     */
    function _repayHelper(uint8 ilkIndex, address repayer, int256 changeInNormalizedDebt) internal {
        // vm.prank(repayer);
        // ionPool.modifyPosition(ilkIndex, repayer, repayer, repayer, 0, changeInNormalizedDebt);
    }
}
