import { EzEthWethHandler } from "./../../../../src/flash/lrt/EzEthWethHandler.sol";
import { Whitelist } from "./../../../../src/Whitelist.sol";
import {
    MAINNET_WSTETH_WETH_UNISWAP,
    EZETH_WETH_BALANCER_POOL_ID,
    EZETH,
    WETH_ADDRESS
} from "./../../../../src/Constants.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { UniswapFlashloanBalancerSwapHandler_Test } from
    "./../../concrete/handlers-base/UniswapFlashloanBalancerSwapHandler.t.sol";
import { IProviderLibraryExposed } from "./../../../helpers/IProviderLibraryExposed.sol";

contract EzEthWethHandler_ForkTest is UniswapFlashloanBalancerSwapHandler_Test {
    EzEthWethHandler handler;
    uint8 immutable ILK_INDEX = 0;

    function setUp() public virtual override {
        super.setUp();
        handler = new EzEthWethHandler(
            ILK_INDEX,
            ionPool,
            gemJoins[ILK_INDEX],
            Whitelist(whitelist),
            MAINNET_WSTETH_WETH_UNISWAP,
            EZETH_WETH_BALANCER_POOL_ID
        );

        EZETH.approve(address(handler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        deal(address(EZETH), address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getCollaterals() internal view override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = EZETH;
    }

    function _getHandler() internal view override returns (address) {
        return address(handler);
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ILK_INDEX;
    }

    function _getUnderlying() internal pure override returns (address) {
        return address(WETH_ADDRESS);
    }

    // NOTE Should be unused
    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return IProviderLibraryExposed(address(0));
    }

    function _getDepositContracts() internal view override returns (address[] memory) {
        return new address[](1);
    }
}

contract EzEthHandler_WithRateChange_ForkTest is EzEthWethHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ILK_INDEX, 3.5708923502395e27);
    }
}
