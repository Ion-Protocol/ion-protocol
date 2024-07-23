// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import { UniswapFlashswapHandler_WithRateChange_FuzzTest } from "../../handlers-base/LrtUniswapFlashswapHandler.t.sol";
import { BaseEzEthWethHandler } from "./../../../../../src/flash/lrt/base/BaseEzEthWethHandler.sol";
import {
    BASE_WETH,
    BASE_EZETH,
    BASE_EZETH_WETH_AERODROME,
    BASE_EZETH_ETH_PRICE_CHAINLINK
} from "./../../../../../src/Constants.sol";
import { Whitelist } from "./../../../../../src/Whitelist.sol";
import { IProviderLibraryExposed } from "./../../../../helpers/IProviderLibraryExposed.sol";

import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

contract BaseEzEthWethHandler_ForkFuzzTest is UniswapFlashswapHandler_WithRateChange_FuzzTest {
    using SafeCast for int256;

    BaseEzEthWethHandler handler;
    uint8 constant ILK_INDEX = 0;

    function setUp() public virtual override {
        super.setUp();

        ufConfig.initialDepositLowerBound = 1 ether;

        handler = new BaseEzEthWethHandler(
            ILK_INDEX,
            ionPool,
            gemJoins[ILK_INDEX],
            Whitelist(whitelist),
            BASE_EZETH_WETH_AERODROME,
            false, // _wethIsToken0
            BASE_WETH
        );

        BASE_EZETH.approve(address(handler), type(uint256).max);

        deal(address(BASE_EZETH), address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getUnderlying() internal pure override returns (address) {
        return address(BASE_WETH);
    }

    function _getCollaterals() internal view override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = BASE_EZETH;
    }

    // Only used for constructing IonRegistry which is now deprecated
    function _getDepositContracts() internal view override returns (address[] memory) {
        address[] memory _depositContracts = new address[](1);
        _depositContracts[0] = address(handler);
        return _depositContracts;
    }

    function _getIlkIndex() internal view override returns (uint8) {
        return ILK_INDEX;
    }

    function _getHandler() internal view override returns (address) {
        return address(handler);
    }

    function _getForkRpc() internal view override returns (string memory) {
        return vm.envString("BASE_MAINNET_RPC_URL");
    }

    // Should be unused
    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return IProviderLibraryExposed(address(0));
    }

    function _getInitialSpotPrice() internal view override returns (uint256) {
        (
            /*uint80 roundID*/
            ,
            int256 ethPerEzEth,
            /*uint startedAt*/
            ,
            uint256 ethPerEzEthUpdatedAt,
            /*uint80 answeredInRound*/
        ) = BASE_EZETH_ETH_PRICE_CHAINLINK.latestRoundData(); // [WAD]

        return ethPerEzEth.toUint256();
    }
}
