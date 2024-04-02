// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonLens } from "../../../src/periphery/IonLens.sol";
import { IIonPool } from "../../../src/interfaces/IIonPool.sol";
import { IGemJoin } from "../../../src/interfaces/IGemJoin.sol";
import { IWhitelist } from "../../../src/interfaces/IWhitelist.sol";
import { IonPool } from "../../../src/IonPool.sol";
import { WEETH_ADDRESS } from "../../../src/Constants.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test } from "forge-std/Test.sol";

contract IonLensTest is Test {
    IonLens public ionLens;
    IIonPool public ionPool = IIonPool(0x0000000000eaEbd95dAfcA37A39fd09745739b78);
    IGemJoin public gemJoin = IGemJoin(0x3f6119B0328C27190bE39597213ea1729f061876);
    IWhitelist public whitelist = IWhitelist(0x7E317f99aA313669AaCDd8dB3927ff3aCB562dAD);
    IonPool public updatedImpl;

    function setUp() public {
        // Pre-upgrade block
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19_494_278);
        ionLens = new IonLens();
        updatedImpl = new IonPool();
    }

    function test_IlkCount() public {
        uint256 ilkCountBefore = ionPool.ilkCount();

        _updateImpl();

        uint256 ilkCountAfter = ionLens.ilkCount(ionPool);

        assertEq(ilkCountBefore, ilkCountAfter, "ilk count");
    }

    function test_getIlkIndex() public {
        uint256 ilkIndexBefore = ionPool.getIlkIndex(address(WEETH_ADDRESS));

        _updateImpl();

        uint256 ilkIndexAfter = ionLens.getIlkIndex(ionPool, address(WEETH_ADDRESS));

        assertEq(ilkIndexBefore, ilkIndexAfter, "ilk index");
    }

    function test_totalNormalizedDebt() public {
        uint8 ilkIndex = 0;
        uint256 totalNormalizedDebtBefore = ionPool.totalNormalizedDebt(ilkIndex);

        _updateImpl();

        uint256 totalNormalizedDebtAfter = ionLens.totalNormalizedDebt(ionPool, ilkIndex);

        assertEq(totalNormalizedDebtBefore, totalNormalizedDebtAfter, "total normalized debt");
    }

    function test_rateUnaccrued() public {
        uint8 ilkIndex = 0;
        uint256 rateUnaccruedBefore = ionPool.rateUnaccrued(ilkIndex);

        _updateImpl();

        uint256 rateUnaccruedAfter = ionLens.rateUnaccrued(ionPool, ilkIndex);

        assertEq(rateUnaccruedBefore, rateUnaccruedAfter, "rate unaccrued");
    }

    function test_lastRateUpdate() public {
        uint8 ilkIndex = 0;
        uint256 lastRateUpdateBefore = ionPool.lastRateUpdate(ilkIndex);

        _updateImpl();

        uint256 lastRateUpdateAfter = ionLens.lastRateUpdate(ionPool, ilkIndex);

        assertEq(lastRateUpdateBefore, lastRateUpdateAfter, "last rate update");
    }

    function test_spot() public {
        uint8 ilkIndex = 0;
        address spotBefore = ionPool.spot(ilkIndex);

        _updateImpl();

        address spotAfter = ionLens.spot(ionPool, ilkIndex);

        assertEq(spotBefore, spotAfter, "spot");
    }

    function test_debtCeiling() public {
        uint8 ilkIndex = 0;
        uint256 debtCeilingBefore = ionPool.debtCeiling(ilkIndex);

        _updateImpl();

        uint256 debtCeilingAfter = ionLens.debtCeiling(ionPool, ilkIndex);

        assertEq(debtCeilingBefore, debtCeilingAfter, "debt ceiling");
    }

    function test_dust() public {
        uint8 ilkIndex = 0;
        uint256 dustBefore = ionPool.dust(ilkIndex);

        _updateImpl();

        uint256 dustAfter = ionLens.dust(ionPool, ilkIndex);

        assertEq(dustBefore, dustAfter, "dust");
    }

    function test_gem() public {
        uint8 ilkIndex = 0;

        address gem = gemJoin.GEM();

        deal(gem, address(this), 1e18);
        IERC20(gem).approve(address(gemJoin), type(uint256).max);
        gemJoin.join(address(this), 1e18);

        uint256 gemBefore = ionPool.gem(ilkIndex, address(this));

        _updateImpl();

        uint256 gemAfter = ionLens.gem(ionPool, ilkIndex, address(this));

        assertEq(gemBefore, gemAfter, "gem");
    }

    function test_unbackedDebt() public {
        uint8 ilkIndex = 0;

        vm.startPrank(whitelist.owner());
        whitelist.updateBorrowersRoot(0, bytes32(0));
        whitelist.updateLendersRoot(bytes32(0));
        vm.stopPrank();

        address base = ionPool.underlying();
        deal(base, address(this), 10e18);
        IERC20(base).approve(address(ionPool), type(uint256).max);
        ionPool.supply(address(this), 10e18, new bytes32[](0));

        address gem = gemJoin.GEM();

        deal(gem, address(this), 10e18);
        IERC20(gem).approve(address(gemJoin), type(uint256).max);
        gemJoin.join(address(this), 10e18);

        ionPool.depositCollateral(ilkIndex, address(this), address(this), 10e18, new bytes32[](0));
        ionPool.borrow(ilkIndex, address(this), address(this), 5e18, new bytes32[](0));

        vm.startPrank(ionPool.defaultAdmin());
        ionPool.grantRole(ionPool.LIQUIDATOR_ROLE(), address(this));
        vm.stopPrank();
        ionPool.confiscateVault(0, address(this), address(this), address(this), 0, -int256(1e14));

        uint256 unbackedDebtBefore = ionPool.unbackedDebt(address(this));

        _updateImpl();

        uint256 unbackedDebtAfter = ionLens.unbackedDebt(ionPool, address(this));

        assertEq(unbackedDebtBefore, unbackedDebtAfter, "unbacked debt");
    }

    function test_isOperator() public {
        address operator = address(2);

        ionPool.addOperator(operator);

        bool isOperatorBefore = ionPool.isOperator(address(this), operator);

        _updateImpl();

        bool isOperatorAfter = ionLens.isOperator(ionPool, address(this), operator);

        assertTrue(isOperatorBefore, "is operator");
        assertEq(isOperatorBefore, isOperatorAfter, "is operator");
    }

    function test_debtUnaccrued() public {
        uint8 ilkIndex = 0;
        uint256 debtUnaccruedBefore = ionPool.debtUnaccrued();

        _updateImpl();

        uint256 debtUnaccruedAfter = ionLens.debtUnaccrued(ionPool);

        assertEq(debtUnaccruedBefore, debtUnaccruedAfter, "debt unaccrued");
    }

    function test_debt() public {
        uint8 ilkIndex = 0;
        uint256 debtBefore = ionPool.debt();

        _updateImpl();

        uint256 debtAfter = ionLens.debt(ionPool);

        assertEq(debtBefore, debtAfter, "debt");
    }

    function test_weth() public {
        uint8 ilkIndex = 0;
        uint256 wethBefore = ionPool.weth();

        _updateImpl();

        uint256 wethAfter = ionLens.weth(ionPool);

        assertEq(wethBefore, wethAfter, "weth");
    }

    function test_wethSupplyCap() public {
        uint8 ilkIndex = 0;
        uint256 wethSupplyCapBefore =
            uint256(vm.load(address(ionPool), 0xceba3d526b4d5afd91d1b752bf1fd37917c20a6daf576bcb41dd1c57c1f67e09));

        _updateImpl();

        uint256 wethSupplyCapAfter = ionLens.wethSupplyCap(ionPool);

        assertEq(wethSupplyCapBefore, wethSupplyCapAfter, "weth supply cap");
    }

    function test_totalUnbackedDebt() public {
        uint256 totalUnbackedDebtBefore = ionPool.totalUnbackedDebt();

        _updateImpl();

        uint256 totalUnbackedDebtAfter = ionLens.totalUnbackedDebt(ionPool);

        assertEq(totalUnbackedDebtBefore, totalUnbackedDebtAfter, "total unbacked debt");
    }

    function test_interestRateModule() public {
        uint8 ilkIndex = 0;
        address interestRateModuleBefore = ionPool.interestRateModule();

        _updateImpl();

        address interestRateModuleAfter = ionLens.interestRateModule(ionPool);

        assertEq(interestRateModuleBefore, interestRateModuleAfter, "interest rate module");
    }

    function test_whitelist() public {
        address whitelistBefore = ionPool.whitelist();

        _updateImpl();

        address whitelistAfter = ionLens.whitelist(ionPool);

        assertEq(whitelistBefore, whitelistAfter, "whitelist");
    }

    function _updateImpl() public {
        vm.store(
            address(ionPool),
            0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
            bytes32(uint256(uint160(address(updatedImpl))))
        );
    }
}
