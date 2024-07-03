import { WeEthWethHandler } from "./../../../../src/flash/lrt/WeEthWethHandler.sol";
import { Whitelist } from "./../../../../src/Whitelist.sol";
import {
    BASE_WSTETH_WETH_UNISWAP,
    BASE_WEETH_WETH_BALANCER_POOL_ID,
    BASE_WETH,
    BASE_WEETH,
    BASE_WEETH_ETH_PRICE_CHAINLINK,
    WETH_ADDRESS
} from "./../../../../src/Constants.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { UniswapFlashloanBalancerSwapHandler_Test } from
    "./../../concrete/handlers-base/UniswapFlashloanBalancerSwapHandler.t.sol";
import { IProviderLibraryExposed } from "./../../../helpers/IProviderLibraryExposed.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

using SafeCast for int256;

contract WeEthWethHandler_ForkTest is UniswapFlashloanBalancerSwapHandler_Test {
    WeEthWethHandler handler;
    uint8 immutable ILK_INDEX = 0;

    function setUp() public virtual override {
        super.setUp();
        handler = new WeEthWethHandler(
            ILK_INDEX,
            ionPool,
            gemJoins[ILK_INDEX],
            Whitelist(whitelist),
            BASE_WSTETH_WETH_UNISWAP,
            BASE_WEETH_WETH_BALANCER_POOL_ID,
            WETH_ADDRESS
        );

        BASE_WEETH.approve(address(handler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        deal(address(BASE_WEETH), address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getCollaterals() internal view override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = BASE_WEETH;
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
        (, int256 ethPerWeEth,,,) = BASE_WEETH_ETH_PRICE_CHAINLINK.latestRoundData(); // [WAD]
        return ethPerWeEth.toUint256();
    }

    // NOTE Should be unused
    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return IProviderLibraryExposed(address(0));
    }

    function _getDepositContracts() internal view override returns (address[] memory) {
        return new address[](1);
    }

    function _getForkRpc() internal view override returns (string memory) {
        return vm.envString("BASE_MAINNET_RPC_URL");
    }
}

contract WeEthWethHandler_WithRateChange_ForkTest is WeEthWethHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ILK_INDEX, 3.5708923502395e27);
    }
}
