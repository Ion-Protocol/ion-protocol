// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { WAD } from "src/libraries/math/WadRayMath.sol";
import { IWstEth, IStaderStakePoolsManager, ISwEth } from "src/interfaces/ProviderInterfaces.sol";
import { IWETH9 } from "src/interfaces/IWETH9.sol";

import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import { IonPoolSharedSetup } from "./IonPoolSharedSetup.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
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

    IWstEth constant MAINNET_WSTETH = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IStaderStakePoolsManager constant MAINNET_STADER =
        IStaderStakePoolsManager(0xcf5EA1b38380f6aF39068375516Daf40Ed70D299);
    ISwEth constant MAINNET_SWELL = ISwEth(0xf951E335afb289353dc249e82926178EaC7DEd78);

    AggregatorV2V3Interface constant STETH_ETH_CHAINLINK =
        AggregatorV2V3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);
    IComposableStableSwapPool constant STADER_POOL =
        IComposableStableSwapPool(0x37b18B10ce5635a84834b26095A0AE5639dCB752);
    IUniswapV3Pool constant SWETH_ETH_POOL = IUniswapV3Pool(0x30eA22C879628514f1494d4BBFEF79D21A6B49A2);

    address constant MAINNET_ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;

    IUniswapV3Factory internal constant FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IWETH9 constant weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IUniswapV3Pool constant WSTETH_WETH_POOL = IUniswapV3Pool(0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa);

    function setUp() public virtual override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        super.setUp();

        (, int256 stEthSpot,,,) = STETH_ETH_CHAINLINK.latestRoundData();
        uint256 wstEthInEthSpot = MAINNET_WSTETH.getStETHByWstETH(uint256(stEthSpot));
        spotOracles[0].setPrice(wstEthInEthSpot);

        uint256 rate = STADER_POOL.getRate();
        spotOracles[1].setPrice(rate);

        (uint160 sqrtPriceX96,,,,,,) = SWETH_ETH_POOL.slot0();
        uint256 oneEthToSwethSpotPrice = uint256(sqrtPriceX96) * sqrtPriceX96 * WAD / (1 << 192); // Spot price OK for
            // testing
        uint256 oneSwethToEthSpotPrice = WAD * WAD / oneEthToSwethSpotPrice;
        spotOracles[2].setPrice(oneSwethToEthSpotPrice);

        vm.deal(lender1, INITIAL_LENDER_UNDERLYING_BALANCE);
        vm.deal(lender2, INITIAL_LENDER_UNDERLYING_BALANCE);

        vm.startPrank(lender1);
        weth.deposit{ value: INITIAL_LENDER_UNDERLYING_BALANCE }();
        weth.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender1, INITIAL_LENDER_UNDERLYING_BALANCE, emptyProof);
        vm.stopPrank();

        vm.startPrank(lender2);
        weth.deposit{ value: INITIAL_LENDER_UNDERLYING_BALANCE }();
        weth.approve(address(ionPool), type(uint256).max);
        ionPool.supply(lender2, INITIAL_LENDER_UNDERLYING_BALANCE, emptyProof);
        vm.stopPrank();

        vm.deal(address(this), INITIAL_THIS_UNDERLYING_BALANCE);
        weth.deposit{ value: INITIAL_THIS_UNDERLYING_BALANCE }();

        IERC20[] memory _collaterals = _getCollaterals();
        for (uint256 i = 0; i < _collaterals.length; i++) {
            _collaterals[i].approve(address(gemJoins[i]), type(uint256).max);
        }
    }

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

    function _getDebtCeiling(uint8) internal pure override returns (uint256) {
        return type(uint256).max;
    }

    receive() external payable { }
}
