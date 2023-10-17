// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPoolSharedSetup } from "../helpers/IonPoolSharedSetup.sol";
import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import { RoundedMath, WAD } from "../../src/math/RoundedMath.sol";
import { ILidoWStEthDeposit, IStaderDeposit, ISwellDeposit } from "../../src/interfaces/DepositInterfaces.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/interfaces/IUniswapV3Pool.sol";
import { IWETH9 } from "../../src/interfaces/IWETH9.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import {console2} from "forge-std/console2.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

struct Slot0 {
    // the current price
    uint160 sqrtPriceX96;
    // the current tick
    int24 tick;
    // the most-recently updated index of the observations array
    uint16 observationIndex;
    // the current maximum number of observations that are being stored
    uint16 observationCardinality;
    // the next maximum number of observations to store, triggered in observations.write
    uint16 observationCardinalityNext;
    // the current protocol fee as a percentage of the swap fee taken on withdrawal
    // represented as an integer denominator (1/x)%
    uint8 feeProtocol;
    // whether the pool is locked
    bool unlocked;
}

interface IComposableStableSwapPool {
    function getRate() external view returns (uint256);
}

abstract contract IonHandler_ForkBase is IonPoolSharedSetup {

    uint256 constant INITIAL_THIS_UNDERLYING_BALANCE = 20e18;

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        super.setUp();

        // Set deposit contracts
        ionRegistry.setDepositContract(0, address(MAINNET_WSTETH));
        ionRegistry.setDepositContract(1, address(MAINNET_STADER));
        ionRegistry.setDepositContract(2, address(MAINNET_SWELL));

        // TODO: Replace with real spotter
        // Simulate spotter
        (, int256 stEthSpot,,,) = STETH_ETH_CHAINLINK.latestRoundData();
        uint256 wstEthInEthSpot = MAINNET_WSTETH.getStETHByWstETH(uint256(stEthSpot));
        console.log(wstEthInEthSpot);
        uint256 riskAdjustedWstEthSpot = wstEthInEthSpot * STETH_LTV / 1e9; // [WAD] * [WAD] / [1e9] = [RAY]
        console.log(riskAdjustedWstEthSpot);
        ionPool.updateIlkSpot(0, riskAdjustedWstEthSpot);

        uint256 rate = STADER_POOL.getRate();
        uint256 riskAdjustedStaderSpot = rate * STADER_LTV / 1e9;
        ionPool.updateIlkSpot(1, riskAdjustedStaderSpot);

        (uint160 sqrtPriceX96,,,,,,) = SWETH_ETH_POOL.slot0();
        uint256 oneEthToSwethSpotPrice = uint256(sqrtPriceX96) * sqrtPriceX96 * WAD / (1 << 192); // Spot price OK for
            // testing
        uint256 oneSwethToEthSpotPrice = WAD * WAD / oneEthToSwethSpotPrice;
        uint256 riskAdjustedSwethSpot = oneSwethToEthSpotPrice * SWELL_LTV / 1e9;
        ionPool.updateIlkSpot(2, riskAdjustedSwethSpot);

        vm.deal(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        vm.deal(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender1);
        weth.deposit{ value: INITIAL_LENDER_UNDERLYING_BALANCE }();
        weth.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        vm.stopPrank();

        vm.startPrank(lender2);
        weth.deposit{ value: INITIAL_LENDER_UNDERLYING_BALANCE }();
        weth.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);
        vm.stopPrank();

        vm.deal(address(this), INITIAL_THIS_UNDERLYING_BALANCE);
        weth.deposit{ value: INITIAL_THIS_UNDERLYING_BALANCE }();
    }
    ILidoWStEthDeposit constant MAINNET_WSTETH = ILidoWStEthDeposit(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IStaderDeposit constant MAINNET_STADER = IStaderDeposit(0xcf5EA1b38380f6aF39068375516Daf40Ed70D299);
    ISwellDeposit constant MAINNET_SWELL = ISwellDeposit(0xf951E335afb289353dc249e82926178EaC7DEd78);

    AggregatorV2V3Interface constant STETH_ETH_CHAINLINK =
        AggregatorV2V3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);
    IComposableStableSwapPool constant STADER_POOL =
        IComposableStableSwapPool(0x37b18B10ce5635a84834b26095A0AE5639dCB752);
    IUniswapV3Pool constant SWETH_ETH_POOL = IUniswapV3Pool(0x30eA22C879628514f1494d4BBFEF79D21A6B49A2);

    address constant MAINNET_ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;

    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    uint256 constant STETH_LTV = 0.92e18;
    uint256 constant STADER_LTV = 0.95e18;
    uint256 constant SWELL_LTV = 0.9e18;

    function _getUnderlying() internal pure override returns (address) {
        return address(weth);
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](3);

        _collaterals[0] = IERC20(address(MAINNET_WSTETH));
        _collaterals[1] = IERC20(address(MAINNET_ETHX));
        _collaterals[2] = IERC20(address(MAINNET_SWELL));
    }

    function _getDepositContracts() internal pure override returns (address[] memory depositContracts) {
        depositContracts = new address[](3);
        depositContracts[0] = address(MAINNET_WSTETH);
        depositContracts[1] = address(MAINNET_STADER);
        depositContracts[2] = address(MAINNET_SWELL);
    }

    receive() external payable { }
}

contract IonHandler_ForkTestFlashLeverage is IonHandler_ForkBase {
    using RoundedMath for uint256;

    function testFork_depositEthFlashLeverageEth() external {
        uint8 ilkIndex = 0;

        uint256 depositAmount = 1e18;
        uint256 leverageAmount = 6e18;

        weth.approve(address(ionHandler), type(uint256).max);
        ionPool.addOperator(address(ionHandler));

        uint256 gasBefore = gasleft();
        ionHandler.flashLeverageWeth(ilkIndex, depositAmount, leverageAmount, true);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        address depositContract = ionRegistry.depositContracts(ilkIndex);
        assertApproxEqAbs(
            ILidoWStEthDeposit(depositContract).getStETHByWstETH(ionPool.collateral(ilkIndex, address(this))),
            depositAmount + leverageAmount,
            2
        );
    }

    function testFork_depositCollateralFlashLeverageEth() external {
        uint8 ilkIndex = 0;

        uint256 depositAmount = 1e18;
        uint256 leverageAmount = 5e18;

        _depositWethForLst(ilkIndex, depositAmount);
        address depositContract = ionRegistry.depositContracts(ilkIndex);
        IERC20(depositContract).approve(address(ionHandler), type(uint256).max);

        ionPool.addOperator(address(ionHandler));

        uint256 gasBefore = gasleft();
        ionHandler.flashLeverageWeth(ilkIndex, depositAmount, leverageAmount, false);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertApproxEqAbs(
            ILidoWStEthDeposit(depositContract).getStETHByWstETH(ionPool.collateral(ilkIndex, address(this))),
            depositAmount + leverageAmount,
            2
        );
    }

    function testFork_depositEthFlashLeverageCollateral() external {
        uint8 ilkIndex = 0;

        uint256 depositAmount = 1e18;
        uint256 leverageAmount = 5e18;

        weth.approve(address(ionHandler), type(uint256).max);
        ionPool.addOperator(address(ionHandler));

        uint256 gasBefore = gasleft();
        ionHandler.flashLeverageCollateral(ilkIndex, depositAmount, leverageAmount, true);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        address depositContract = ionRegistry.depositContracts(ilkIndex);
        assertApproxEqAbs(
            ILidoWStEthDeposit(depositContract).getStETHByWstETH(ionPool.collateral(ilkIndex, address(this))),
            depositAmount + leverageAmount,
            2
        );
    }

    function testFork_depositCollateralFlashLeverageCollateral() external {
        uint8 ilkIndex = 0;

        uint256 depositAmount = 1e18;
        uint256 leverageAmount = 5e18;

        _depositWethForLst(ilkIndex, depositAmount);
        address depositContract = ionRegistry.depositContracts(ilkIndex);
        IERC20(depositContract).approve(address(ionHandler), type(uint256).max);

        ionPool.addOperator(address(ionHandler));

        uint256 gasBefore = gasleft();
        ionHandler.flashLeverageCollateral(ilkIndex, depositAmount, leverageAmount, false);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        assertApproxEqAbs(
            ILidoWStEthDeposit(depositContract).getStETHByWstETH(ionPool.collateral(ilkIndex, address(this))),
            depositAmount + leverageAmount,
            2
        );
    }

    function _depositWethForLst(uint8 ilkIndex, uint256 amount) internal {
        weth.withdraw(amount);
        address payable depositContract = payable(ionRegistry.depositContracts(ilkIndex));

        if (ilkIndex == 0) {
            (bool success,) = depositContract.call{ value: amount }("");
            require(success);
        } else if (ilkIndex == 1) {
            IStaderDeposit(depositContract).deposit{ value: amount }(address(this));
        } else if (ilkIndex == 2) {
            ISwellDeposit(depositContract).deposit{ value: amount }();
        } else {
            revert("Invalid ilkIndex");
        }
    }

}

contract IonHandler_ForkFuzzTestFlashLeverage is IonHandler_ForkBase {
    using RoundedMath for uint256;

    function setUp() public override {
        super.setUp();

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < ionPool.ilkCount(); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }
    }

    /// forge-config: default.fuzz.runs = 10000
    function testForkFuzz_depositEthFlashLeverageEth(uint256 depositAmount, uint256 leverageMultiplier) external {
        uint8 ilkIndex = 0;

        depositAmount = bound(depositAmount, 4 wei, INITIAL_THIS_UNDERLYING_BALANCE);
        leverageMultiplier = bound(leverageMultiplier, 1, 8);
        uint256 leverageAmount = depositAmount * leverageMultiplier;

        weth.approve(address(ionHandler), type(uint256).max);
        ionPool.addOperator(address(ionHandler));

        uint256 gasBefore = gasleft();
        ionHandler.flashLeverageWeth(ilkIndex, depositAmount, leverageAmount, true);
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        address depositContract = ionRegistry.depositContracts(ilkIndex);
        assertApproxEqAbs(
            ILidoWStEthDeposit(depositContract).getStETHByWstETH(ionPool.collateral(ilkIndex, address(this))),
            depositAmount + leverageAmount,
            2
        );
    } 
}
