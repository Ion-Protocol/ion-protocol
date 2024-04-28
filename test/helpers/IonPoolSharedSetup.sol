// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IonPool } from "../../src/IonPool.sol";
import { IonLens } from "../../src/periphery/IonLens.sol";
import { IonRegistry } from "../../src/periphery/IonRegistry.sol";
import { InterestRate, IlkData, SECONDS_IN_A_YEAR } from "../../src/InterestRate.sol";
import { IYieldOracle } from "../../src/interfaces/IYieldOracle.sol";
import { IIonPool } from "../../src/interfaces/IIonPool.sol";
import { GemJoin } from "../../src/join/GemJoin.sol";
import { WadRayMath, WAD } from "../../src/libraries/math/WadRayMath.sol";
import { Whitelist } from "../../src/Whitelist.sol";
import { SpotOracle } from "../../src/oracles/spot/SpotOracle.sol";
import { BaseTestSetup } from "../helpers/BaseTestSetup.sol";
import { YieldOracleSharedSetup } from "../helpers/YieldOracleSharedSetup.sol";
import { ERC20PresetMinterPauser } from "../helpers/ERC20PresetMinterPauser.sol";
import { Solarray } from "solarray/Solarray.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

using WadRayMath for uint16;

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
    uint32 immutable APY;

    constructor(uint32 apy) {
        APY = apy;
    }

    function apys(uint256) external view returns (uint32) {
        return APY;
    }
}

contract IonPoolExposed is IonPool {
    function setRate(uint8 ilkIndex, uint104 newRate) external {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 oldRate = $.ilks[ilkIndex].rate;
        $.ilks[ilkIndex].rate = newRate;

        uint256 rateDiff = newRate - oldRate;
        $.debt += rateDiff * $.ilks[ilkIndex].totalNormalizedDebt;
    }

    function setSupplyFactor(uint256 factor) external {
        _setSupplyFactor(factor);
    }

    function addLiquidity(uint256 amount) external {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.liquidity += amount;
    }
}

contract MockSpotOracle is SpotOracle {
    uint256 price;

    constructor(uint256 ltv, address reserveOracle, uint256 _price) SpotOracle(ltv, reserveOracle) {
        price = _price;
    }

    function getPrice() public view override returns (uint256) {
        return price;
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }
}

contract MockReserveOracle {
    uint256 public currentExchangeRate;

    constructor(uint256 _exchangeRate) {
        currentExchangeRate = _exchangeRate;
    }

    function setExchangeRate(uint256 _exchangeRate) public {
        currentExchangeRate = _exchangeRate;
    }
}

struct Config {
    uint128[] minimumProfitMargins;
    uint128[] minimumKinkRates;
    uint16[] reserveFactors;
    uint128[] adjustedBaseRates;
    uint128[] minimumBaseRates;
    uint16[] optimalUtilizationRates;
    uint16[] distributionFactors;
    uint128[] adjustedAboveKinkSlopes;
    uint128[] minimumAboveKinkSlopes;
}

abstract contract IonPoolSharedSetup is BaseTestSetup, YieldOracleSharedSetup {
    Config config;

    IIonPool iIonPool;
    IonPoolExposed ionPool;
    IonPoolExposed ionPoolImpl;
    IonRegistry ionRegistry;

    InterestRate interestRateModule;
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
    uint256 internal constant PRICE = 1e18; // [wad] market price
    uint256 internal constant LTV = 1e27; // [ray] max LTV for a position
    uint256 internal constant EXCHANGE_RATE = 1e18; // [wad]
    uint80 internal constant minimumProfitMargin = 0.85e18 / SECONDS_IN_A_YEAR;
    uint256 internal constant DUST = 0; // [rad]

    uint256 internal constant INITIAL_LENDER_UNDERLYING_BALANCE = 100e18;
    uint256 internal constant INITIAL_BORROWER_COLLATERAL_BALANCE = 100e18;

    ERC20PresetMinterPauser immutable wstEth = new ERC20PresetMinterPauser("Staked Ether", "stETH");
    ERC20PresetMinterPauser immutable ethX = new ERC20PresetMinterPauser("Ether X", "ETHX");
    ERC20PresetMinterPauser immutable swEth = new ERC20PresetMinterPauser("Swell Ether", "swETH");

    ERC20PresetMinterPauser[] internal mintableCollaterals = [wstEth, ethX, swEth];

    uint96 internal constant wstEthMinimumProfitMargin = 70_677_685_926_057_170; // 7.0677685926057170E-11 in RAY
    uint96 internal constant ethXMinimumProfitMargin = 91_263_663_293_261_740; // 9.1263663293261740E-11 in RAY
    uint96 internal constant swEthMinimumProfitMargin = 81_452_622_424_649_230; // 8.145262242464923e-11 in RAY

    uint96 internal constant wstEthAdjustedAboveKinkSlope = 25_017_682_370_176_442_000; // 2.5017682370176444e-08 in RAY
    uint96 internal constant ethXAdjustedAboveKinkSlope = 39_693_222_042_558_280_000; // 3.9693222042558285e-08 in RAY
    uint96 internal constant swEthAdjustedAboveKinkSlope = 21_397_408_289_658_417_000; // 2.1397408289658418e-08 in RAY

    uint96 internal constant wstEthMinimumAboveKinkSlope = 26_390_655_175_013_278_000;
    uint96 internal constant ethXMinimumAboveKinkSlope = 48_899_593_146_619_404_000;
    uint96 internal constant swEthMinimumAboveKinkSlope = 21_366_508_315_720_827_000;

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
    uint256[] internal debtCeilings = [wstEthDebtCeiling, ethXDebtCeiling, swEthDebtCeiling];

    IERC20[] internal collaterals;
    GemJoin[] internal gemJoins;
    MockSpotOracle[] internal spotOracles;

    IonLens lens;

    constructor() {
        lens = new IonLens();
        vm.makePersistent(address(lens));

        config.minimumProfitMargins =
            Solarray.uint128s(wstEthMinimumProfitMargin, ethXMinimumProfitMargin, swEthMinimumProfitMargin);
        config.minimumKinkRates = Solarray.uint16s(0, 0, 0);
        config.reserveFactors =
            Solarray.uint16s(wstEthAdjustedReserveFactor, ethXAdjustedReserveFactor, swEthAdjustedReserveFactor);
        config.adjustedBaseRates = Solarray.uint128s(0, 0, 0);
        config.minimumBaseRates = Solarray.uint128s(0, 0, 0);
        config.optimalUtilizationRates =
            Solarray.uint16s(wstEthOptimalUtilizationRate, ethXOptimalUtilizationRate, swEthOptimalUtilizationRate);
        config.distributionFactors =
            Solarray.uint16s(wstEthDistributionFactor, ethXDistributionFactor, swEthDistributionFactor);
        config.adjustedAboveKinkSlopes =
            Solarray.uint128s(wstEthAdjustedAboveKinkSlope, ethXAdjustedAboveKinkSlope, swEthAdjustedAboveKinkSlope);
        config.minimumAboveKinkSlopes =
            Solarray.uint128s(wstEthMinimumAboveKinkSlope, ethXMinimumAboveKinkSlope, swEthMinimumAboveKinkSlope);
    }

    IlkData[] ilkConfigs;

    function setUp() public virtual override(BaseTestSetup, YieldOracleSharedSetup) {
        collaterals = _getCollaterals();
        address[] memory depositContracts = _getDepositContracts();

        assert(
            collaterals.length == config.reserveFactors.length
                && config.reserveFactors.length == config.optimalUtilizationRates.length
                && config.optimalUtilizationRates.length == config.distributionFactors.length
                && config.distributionFactors.length == debtCeilings.length
        );
        BaseTestSetup.setUp();
        YieldOracleSharedSetup.setUp();
        apyOracle = _getYieldOracle();

        uint256 distributionFactorSum;

        IlkData memory ilkConfig;
        for (uint256 i = 0; i < collaterals.length; i++) {
            ilkConfig = IlkData({
                adjustedProfitMargin: uint96(config.minimumProfitMargins[i]),
                minimumKinkRate: uint96(config.minimumKinkRates[i]),
                reserveFactor: config.reserveFactors[i],
                adjustedBaseRate: uint96(config.adjustedBaseRates[i]),
                minimumBaseRate: uint96(config.minimumBaseRates[i]),
                optimalUtilizationRate: config.optimalUtilizationRates[i],
                distributionFactor: config.distributionFactors[i],
                adjustedAboveKinkSlope: uint96(config.adjustedAboveKinkSlopes[i]),
                minimumAboveKinkSlope: uint96(config.minimumAboveKinkSlopes[i])
            });

            ilkConfigs.push(ilkConfig);

            distributionFactorSum += config.distributionFactors[i];
        }

        assert(distributionFactorSum == 1e4);

        interestRateModule = new InterestRate(ilkConfigs, apyOracle);

        // whitelist
        whitelist = address(_getWhitelist());

        // Instantiate upgradeable IonPool
        ProxyAdmin ionProxyAdmin = new ProxyAdmin(address(this));

        // Instantiate upgradeable IonPool
        ionPoolImpl = new IonPoolExposed();

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
        iIonPool = IIonPool(address(ionPool));

        ionPool.grantRole(ionPool.ION(), address(this));
        ionPool.grantRole(ionPool.PAUSE_ROLE(), address(this));
        ionPool.updateSupplyCap(type(uint256).max);

        for (uint8 i = 0; i < collaterals.length; i++) {
            ionPool.initializeIlk(address(collaterals[i]));
            SpotOracle spotOracle = _getSpotOracle();
            spotOracles.push(MockSpotOracle(address(spotOracle)));
            ionPool.updateIlkSpot(i, spotOracle);
            ionPool.updateIlkDebtCeiling(i, _getDebtCeiling(i));

            gemJoins.push(new GemJoin(ionPool, collaterals[i], i, address(this)));

            ionPool.grantRole(ionPool.GEM_JOIN_ROLE(), address(gemJoins[i]));
            ilkIndexes[address(collaterals[i])] = i;
        }

        ionRegistry = new IonRegistry(gemJoins, depositContracts, address(this));
    }

    function test_SetUp() public virtual override {
        super.test_SetUp();
        assertEq(address(ionPool.underlying()), _getUnderlying(), "underlying");
        assertEq(ionPool.implementation(), address(ionPoolImpl), "implementation");

        // attempt to initialize again
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        ionPool.initialize(
            _getUnderlying(),
            TREASURY,
            DECIMALS,
            NAME,
            SYMBOL,
            address(this),
            InterestRate(address(0)),
            Whitelist(whitelist)
        );

        assertEq(ionPool.treasury(), TREASURY, "treasury");
        assertEq(ionPool.decimals(), DECIMALS, "decimals");
        assertEq(ionPool.name(), NAME, "name");
        assertEq(ionPool.symbol(), SYMBOL, "symbol");
        assertEq(ionPool.defaultAdmin(), address(this), "default admin");

        assertEq(lens.ilkCount(iIonPool), collaterals.length, "ilk count");

        assertEq(ionPool.paused(), false, "pause");

        for (uint8 i = 0; i < collaterals.length; i++) {
            address collateralAddress = address(collaterals[i]);
            assertEq(ionPool.getIlkAddress(i), collateralAddress, "ilk address");
            assertEq(lens.getIlkIndex(iIonPool, collateralAddress), ilkIndexes[collateralAddress], "ilk index");

            // assertEq(ionPool.totalNormalizedDebt(i), 0);
            // assertEq(ionPool.rate(i), 1e27);
            assertEq(address(lens.spot(iIonPool, i)), address(spotOracles[i]), "spot oracle");

            assertEq(lens.debtCeiling(iIonPool, i), _getDebtCeiling(i), "debt ceiling");
            assertEq(ionPool.dust(i), DUST, "dust");

            // (uint256 borrowRate, uint256 reserveFactor) = ionPool.getCurrentBorrowRate(i);
            // assertEq(borrowRate, 1 * RAY);
            // assertEq(reserveFactor, adjustedReserveFactors[i].scaleUpToRay(4));

            IlkData memory ilkConfig = interestRateModule.unpackCollateralConfig(i);
            assertEq(ilkConfig.adjustedProfitMargin, config.minimumProfitMargins[i], "minimum profit margin");
            assertEq(ilkConfig.minimumKinkRate, config.minimumKinkRates[i], "minimum kink rate");

            assertEq(ilkConfig.reserveFactor, config.reserveFactors[i], "reserve factor");
            assertEq(ilkConfig.adjustedBaseRate, config.adjustedBaseRates[i], "adjusted base rate");
            assertEq(ilkConfig.minimumBaseRate, config.minimumBaseRates[i], "minimum base rate");
            assertEq(ilkConfig.optimalUtilizationRate, config.optimalUtilizationRates[i], "optimal utilization rate");
            assertEq(ilkConfig.distributionFactor, config.distributionFactors[i], "distribution factor");

            assertEq(ilkConfig.adjustedAboveKinkSlope, config.adjustedAboveKinkSlopes[i], "adjusted above kink slope");
            assertEq(ilkConfig.minimumAboveKinkSlope, config.minimumAboveKinkSlopes[i], "minimum above kink slope");
        }

        assertEq(interestRateModule.COLLATERAL_COUNT(), collaterals.length, "collateral count");
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

    function _getYieldOracle() internal virtual returns (IYieldOracle) {
        return new MockYieldOracle(3.45e6);
    }

    function _getSpotOracle() internal virtual returns (SpotOracle) {
        return new MockSpotOracle(LTV, address(new MockReserveOracle(EXCHANGE_RATE)), PRICE);
    }

    function _getWhitelist() internal virtual returns (Whitelist) {
        return new Whitelist(new bytes32[](0), bytes32(0));
    }

    function _getSpot() internal view virtual returns (uint256) {
        return PRICE * LTV / WAD;
    }

    function _getDebtCeiling(uint8 ilkIndex) internal view virtual returns (uint256) {
        return debtCeilings[ilkIndex];
    }

    function _getDepositContracts() internal view virtual returns (address[] memory) {
        return new address[](3);
    }

    function _depositInterestGains(uint256 amount) public {
        ionPool.addLiquidity(amount);
        underlying.mint(address(ionPool), amount);
    }
}
