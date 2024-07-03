// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWstEth, IStEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { IWETH9 } from "../../../src/interfaces/IWETH9.sol";
import { IProviderLibraryExposed } from "../../helpers/IProviderLibraryExposed.sol";
import { IonPoolSharedSetup } from "../IonPoolSharedSetup.sol";

import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import { WETH_ADDRESS } from "./../../../src/Constants.sol";

abstract contract IonHandler_ForkBase is IonPoolSharedSetup {
    uint256 constant INITIAL_THIS_UNDERLYING_BALANCE = 20e18;

    IStEth constant MAINNET_STETH = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstEth constant MAINNET_WSTETH = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    IUniswapV3Pool constant WSTETH_WETH_POOL = IUniswapV3Pool(0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa);

    AggregatorV2V3Interface constant STETH_ETH_CHAINLINK =
        AggregatorV2V3Interface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);

    IWETH9 internal weth = IWETH9(_getUnderlying());

    uint256 forkBlock = 0;

    bytes32[] borrowerWhitelistProof;

    function setUp() public virtual override {
        if (forkBlock == 0) vm.createSelectFork(_getForkRpc());
        else vm.createSelectFork(_getForkRpc(), forkBlock);
        super.setUp();

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

    /**
     * The asset that the lenders deposit into the IonPool. By default, the test
     * assumes the base asset is WETH.
     */
    function _getUnderlying() internal pure virtual override returns (address) {
        return address(WETH_ADDRESS);
    }

    function _getDebtCeiling(uint8) internal pure override returns (uint256) {
        return type(uint256).max;
    }

    function _getIlkIndex() internal view virtual returns (uint8);

    function _getProviderLibrary() internal view virtual returns (IProviderLibraryExposed);

    function _getHandler() internal view virtual returns (address);

    function _getForkRpc() internal view virtual returns (string memory) {
        return vm.envString("MAINNET_ARCHIVE_RPC_URL");
    }

    receive() external payable { }
}
