// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "src/IonPool.sol";
import { IonPausableUpgradeable } from "src/admin/IonPausableUpgradeable.sol";
import { IonRegistry } from "src/periphery/IonRegistry.sol";
import { InterestRate, IlkData, SECONDS_IN_A_DAY } from "src/InterestRate.sol";
import { IYieldOracle } from "src/interfaces/IYieldOracle.sol";
import { GemJoin } from "src/join/GemJoin.sol";
import { RoundedMath, RAY } from "src/libraries/math/RoundedMath.sol";
import { Whitelist } from "src/Whitelist.sol";
import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";

import { BaseTestSetup } from "test/helpers/BaseTestSetup.sol";
import { YieldOracleSharedSetup } from "test/helpers/YieldOracleSharedSetup.sol";
import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";
import { console2 } from "forge-std/console2.sol";

using RoundedMath for uint16;

// struct IlkData {
//                                                        _
//     uint96 adjustedProfitMargin; // 27 decimals         |
//     uint96 minimumKinkRate; // 27 decimals              |
//     uint24 adjustedAboveKinkSlope; // 4 decimals        |   256 bits
//     uint24 minimumAboveKinkSlope; // 4 decimals         |
//     uint16 adjustedReserveFactor; // 4 decimals        _|
//                                                         |
//     uint16 minimumReserveFactor; // 4 decimals          |
//     uint96 adjustedBaseRate; // 27 decimals             |   240 bits
//     uint96 minimumBaseRate; // 27 decimals              |
//     uint16 optimalUtilizationRate; // 4 decimals        |
//     uint16 distributionFactor; // 4 decimals           _|
// }

contract MockYieldOracle is IYieldOracle {
    uint32 APY = 3.45e6;

    function apys(uint256) external view returns (uint32) {
        return APY;
    }
}

contract InterestRateExposed is InterestRate {
    constructor(IlkData[] memory ilks, IYieldOracle apyOracle) InterestRate(ilks, apyOracle) { }

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

    function setRate(uint8 ilkIndex, uint104 newRate) external {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.ilks[ilkIndex].rate = newRate;
    }

    function setSupplyFactor(uint256 factor) external {
        _setSupplyFactor(factor);
    }
}

// for bypassing whitelist checks during tests
contract MockWhitelist {
    function isWhitelistedBorrower(uint8, address, bytes32[] calldata) external pure returns (bool) {
        return true;
    }

    function isWhitelistedLender(address, bytes32[] calldata) external pure returns (bool) {
        return true;
    }
}

contract MockSpotOracle is SpotOracle {
    uint256 price;

    constructor(uint8 ilkIndex, uint256 ltv, uint256 _price) SpotOracle(ilkIndex, ltv) {
        price = _price;
    }

    function getPrice() public view override returns (uint256) {
        return price;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }
}

abstract contract IonPoolSharedSetup is BaseTestSetup, YieldOracleSharedSetup {
    IonPoolExposed ionPool;
    IonPoolExposed ionPoolImpl;
    IonRegistry ionRegistry;

    InterestRateExposed interestRateModule;
    IYieldOracle apyOracle;

    mapping(address ilkAddress => uint8 ilkIndex) public ilkIndexes;

    address immutable lender1 = vm.addr(1);
    address immutable lender2 = vm.addr(2);
    address immutable borrower1 = vm.addr(3);
    address immutable borrower2 = vm.addr(4);

    // --- Whitelist ---
    address internal whitelist;
    bytes32[] internal emptyProof;

    // --- Configs ---
    uint256 internal constant SPOT = 1e27; // [ray]
    uint80 internal constant minimumProfitMargin = 0.85e18 / SECONDS_IN_A_DAY;

    uint256 internal constant INITIAL_LENDER_UNDERLYING_BALANCE = 100e18;
    uint256 internal constant INITIAL_BORROWER_COLLATERAL_BALANCE = 100e18;

    ERC20PresetMinterPauser immutable wstEth = new ERC20PresetMinterPauser("Staked Ether", "stETH");
    ERC20PresetMinterPauser immutable ethX = new ERC20PresetMinterPauser("Ether X", "ETHX");
    ERC20PresetMinterPauser immutable swEth = new ERC20PresetMinterPauser("Swell Ether", "swETH");

    ERC20PresetMinterPauser[] internal mintableCollaterals = [wstEth, ethX, swEth];

    uint16 internal constant wstEthAdjustedReserveFactor = 0.1e4;
    uint16 internal constant ethXAdjustedReserveFactor = 0.05e4;
    uint16 internal constant swEthAdjustedReserveFactor = 0.08e4;

    uint16 internal constant wstEthOptimalUtilizationRate = 0.9e4;
    uint16 internal constant ethXOptimalUtilizationRate = 0.95e4;
    uint16 internal constant swEthOptimalUtilizationRate = 0.92e4;

    uint16 internal wstEthDistributionFactor = 0.2e4;
    uint16 internal ethXDistributionFactor = 0.4e4;
    uint16 internal swEthDistributionFactor = 0.4e4;

    uint256 internal wstEthDebtCeiling = 20e45;
    uint256 internal ethXDebtCeiling = 40e45;
    uint256 internal swEthDebtCeiling = 40e45;

    IERC20[] internal collaterals;
    GemJoin[] internal gemJoins;
    uint16[] internal adjustedReserveFactors =
        [wstEthAdjustedReserveFactor, ethXAdjustedReserveFactor, swEthAdjustedReserveFactor];
    uint16[] internal optimalUtilizationRates =
        [wstEthOptimalUtilizationRate, ethXOptimalUtilizationRate, swEthOptimalUtilizationRate];
    uint16[] internal distributionFactors = [wstEthDistributionFactor, ethXDistributionFactor, swEthDistributionFactor];
    uint256[] internal debtCeilings = [wstEthDebtCeiling, ethXDebtCeiling, swEthDebtCeiling];
    MockSpotOracle[] internal spotOracles;

    IlkData[] ilkConfigs;

    function setUp() public virtual override(BaseTestSetup, YieldOracleSharedSetup) {
        collaterals = _getCollaterals();
        address[] memory depositContracts = _getDepositContracts();

        assert(
            collaterals.length == adjustedReserveFactors.length
                && adjustedReserveFactors.length == optimalUtilizationRates.length
                && optimalUtilizationRates.length == distributionFactors.length
                && distributionFactors.length == debtCeilings.length
        );
        BaseTestSetup.setUp();
        YieldOracleSharedSetup.setUp();
        apyOracle = new MockYieldOracle();

        uint256 distributionFactorSum;

        IlkData memory ilkConfig;
        for (uint256 i = 0; i < collaterals.length; i++) {
            ilkConfig = IlkData({
                adjustedProfitMargin: minimumProfitMargin,
                minimumKinkRate: 0,
                adjustedAboveKinkSlope: 700e4,
                minimumAboveKinkSlope: 700e4,
                adjustedReserveFactor: adjustedReserveFactors[i],
                minimumReserveFactor: adjustedReserveFactors[i],
                minimumBaseRate: 0,
                adjustedBaseRate: 0,
                optimalUtilizationRate: optimalUtilizationRates[i],
                distributionFactor: distributionFactors[i]
            });

            ilkConfigs.push(ilkConfig);

            distributionFactorSum += distributionFactors[i];
        }

        assert(distributionFactorSum == 1e4);

        interestRateModule = new InterestRateExposed(ilkConfigs, apyOracle);

        // whitelist
        whitelist = address(new MockWhitelist());

        // Instantiate upgradeable IonPool
        ProxyAdmin ionProxyAdmin = new ProxyAdmin(address(this));
        // Instantiate upgradeable IonPool
        ionPoolImpl =
            new IonPoolExposed(_getUnderlying(), TREASURY, DECIMALS, NAME, SYMBOL, address(this), interestRateModule);

        bytes memory initializeBytes = abi.encodeWithSelector(
            IonPool.initialize.selector,
            _getUnderlying(),
            TREASURY,
            DECIMALS,
            NAME,
            SYMBOL,
            address(this),
            interestRateModule,
            whitelist
        );
        ionPool = IonPoolExposed(
            address(new TransparentUpgradeableProxy(address(ionPoolImpl), address(ionProxyAdmin), initializeBytes))
        );
        vm.label(address(ionPool), "IonPool");

        ionPool.grantRole(ionPool.ION(), address(this));
        ionPool.updateSupplyCap(type(uint256).max);

        for (uint8 i = 0; i < collaterals.length; i++) {
            ionPool.initializeIlk(address(collaterals[i]));
            MockSpotOracle spotOracle = new MockSpotOracle(i, 1e18, SPOT / 1e9);
            spotOracles.push(spotOracle);
            ionPool.updateIlkSpot(i, spotOracle);
            ionPool.updateIlkDebtCeiling(i, debtCeilings[i]);

            gemJoins.push(new GemJoin(ionPool, collaterals[i], i, address(this)));

            ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(gemJoins[i]));
            ilkIndexes[address(collaterals[i])] = i;
        }

        ionRegistry = new IonRegistry(gemJoins, depositContracts, address(this));
    }

    function test_setUp() public virtual override {
        super.test_setUp();
        assertEq(address(ionPool.underlying()), _getUnderlying());
        assertEq(ionPool.implementation(), address(ionPoolImpl));

        // attempt to initialize again
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ionPool.initialize(
            _getUnderlying(), TREASURY, DECIMALS, NAME, SYMBOL, address(this), interestRateModule, Whitelist(whitelist)
        );

        assertEq(ionPool.treasury(), TREASURY);
        assertEq(ionPool.decimals(), DECIMALS);
        assertEq(ionPool.name(), NAME);
        assertEq(ionPool.symbol(), SYMBOL);
        assertEq(ionPool.defaultAdmin(), address(this));

        assertEq(ionPool.ilkCount(), collaterals.length);

        assertEq(ionPool.paused(IonPausableUpgradeable.Pauses.UNSAFE), false);
        assertEq(ionPool.paused(IonPausableUpgradeable.Pauses.SAFE), false);

        uint256 addressesLength = ionPool.addressesLength();
        assertEq(addressesLength, collaterals.length);
        for (uint8 i = 0; i < addressesLength; i++) {
            address collateralAddress = address(collaterals[i]);
            assertEq(ionPool.addressContains(collateralAddress), true);
            assertEq(ionPool.getIlkAddress(i), collateralAddress);
            assertEq(ionPool.getIlkIndex(collateralAddress), ilkIndexes[collateralAddress]);

            assertEq(ionPool.totalNormalizedDebt(i), 0);
            // assertEq(ionPool.rate(i), 1e27);
            // assertEq(ionPool.spot(i).getSpot(), SPOT);
            assertEq(address(ionPool.spot(i)), address(spotOracles[i]));
            assertEq(ionPool.debtCeiling(i), _getDebtCeiling(i));
            assertEq(ionPool.dust(i), 0);

            (uint256 borrowRate, uint256 reserveFactor) = ionPool.getCurrentBorrowRate(i);
            assertEq(borrowRate, 1 * RAY);
            assertEq(reserveFactor, adjustedReserveFactors[i].scaleUpToRay(4));

            IlkData memory ilkConfig = interestRateModule.unpackCollateralConfig(i);
            assertEq(ilkConfig.adjustedProfitMargin, minimumProfitMargin);
            assertEq(ilkConfig.minimumKinkRate, 0);
            assertEq(ilkConfig.adjustedAboveKinkSlope, 700e4);
            assertEq(ilkConfig.minimumAboveKinkSlope, 700e4);
            assertEq(ilkConfig.adjustedReserveFactor, adjustedReserveFactors[i]);
            assertEq(ilkConfig.minimumReserveFactor, adjustedReserveFactors[i]);
            assertEq(ilkConfig.minimumBaseRate, 0);
            assertEq(ilkConfig.adjustedBaseRate, 0);
            assertEq(ilkConfig.optimalUtilizationRate, optimalUtilizationRates[i]);
            assertEq(ilkConfig.distributionFactor, distributionFactors[i]);
        }

        assertEq(interestRateModule.collateralCount(), collaterals.length);
    }

    function _getUnderlying() internal view virtual returns (address) {
        return address(underlying);
    }

    function _getCollaterals() internal view virtual returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](3);

        _collaterals[0] = IERC20(address(wstEth));
        _collaterals[1] = IERC20(address(ethX));
        _collaterals[2] = IERC20(address(swEth));
    }

    function _getDebtCeiling(uint8 ilkIndex) internal view virtual returns (uint256) {
        return debtCeilings[ilkIndex];
    }

    function _getDepositContracts() internal view virtual returns (address[] memory) {
        return new address[](3);
    }
}
