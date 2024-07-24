pragma solidity ^0.8.21;

import { BaseRsEthHandler } from "../../../../../src/flash/lrt/BaseRsEthHandler.sol";
import { Whitelist } from "../../../../../src/Whitelist.sol";
import {
    BASE_RSETH_WETH_AERODROME,
    BASE_WETH,
    BASE_RSETH,
    BASE_RSETH_ETH_PRICE_CHAINLINK
} from "../../../../../src/Constants.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { AerodromeFlashswapHandler_Test } from
    "../../../concrete/handlers-base/AerodromeFlashswapHandler.t.sol";
import { IProviderLibraryExposed } from "../../../../helpers/IProviderLibraryExposed.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IPool} from "../../../../../src/interfaces/IPool.sol";

using SafeCast for int256;

contract RsEthWethHandler_ForkTest is AerodromeFlashswapHandler_Test {
    BaseRsEthHandler handler;
    uint8 immutable ILK_INDEX = 0;

    function setUp() public virtual override {
        super.setUp();
        handler = new BaseRsEthHandler(
            ILK_INDEX,
            ionPool,
            gemJoins[ILK_INDEX],
            Whitelist(whitelist),
            BASE_RSETH_WETH_AERODROME,
            BASE_WETH
        );

        BASE_RSETH.approve(address(handler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        deal(address(BASE_RSETH), address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = BASE_RSETH;
    }

    function _getHandler() internal view override returns (address) {
        return address(handler);
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ILK_INDEX;
    }

    function _getUnderlying() internal pure override returns (address) {
        return address(BASE_WETH);
    }

    function _getInitialSpotPrice() internal view override returns (uint256) {
        (, int256 ethPerRsEth,,,) = BASE_RSETH_ETH_PRICE_CHAINLINK.latestRoundData(); // [WAD]
        return ethPerRsEth.toUint256();
    }

    // NOTE Should be unused
    function _getProviderLibrary() internal pure override returns (IProviderLibraryExposed) {
        return IProviderLibraryExposed(address(0));
    }

    function _getDepositContracts() internal pure override returns (address[] memory) {
        return new address[](1);
    }

    function _getForkRpc() internal view override returns (string memory) {
        return vm.envString("BASE_MAINNET_RPC_URL");
    }
}

contract RsEthHandler_WithRateChange_ForkTest is RsEthWethHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ILK_INDEX, 3.5708923502395e27);
    }
}
