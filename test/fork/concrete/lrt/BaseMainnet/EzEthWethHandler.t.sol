import { EzEthHandlerBaseChain } from "../../../../../src/flash/lrt/EzEthHandlerBaseChain.sol";
import { Whitelist } from "../../../../../src/Whitelist.sol";
import {
    BASE_EZTETH_WETH_AERODROME,
    BASE_WETH,
    BASE_EZETH,
    BASE_EZETH_ETH_PRICE_CHAINLINK
} from "../../../../../src/Constants.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

import { AerodromeFlashswapHandler_Test } from
    "../../../concrete/handlers-base/AerodromeFlashswapHandler.t.sol";
import { IProviderLibraryExposed } from "../../../../helpers/IProviderLibraryExposed.sol";
import { SafeCast } from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IPool} from "../../../../../src/interfaces/IPool.sol";

using SafeCast for int256;

contract EzEthWethHandler_ForkTest is AerodromeFlashswapHandler_Test {
    EzEthHandlerBaseChain handler;
    uint8 immutable ILK_INDEX = 0;

    function setUp() public virtual override {
        super.setUp();
        handler = new EzEthHandlerBaseChain(
            ILK_INDEX,
            ionPool,
            gemJoins[ILK_INDEX],
            Whitelist(whitelist),
            BASE_EZTETH_WETH_AERODROME,
            BASE_WETH
        );

        BASE_EZETH.approve(address(handler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        deal(address(BASE_EZETH), address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](1);
        _collaterals[0] = BASE_EZETH;
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
        (, int256 ethPerEzEth,,,) = BASE_EZETH_ETH_PRICE_CHAINLINK.latestRoundData(); // [WAD]
        return ethPerEzEth.toUint256();
    }

    // NOTE Should be unused
    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return IProviderLibraryExposed(address(0));
    }

    function _getDepositContracts() internal pure override returns (address[] memory) {
        return new address[](1);
    }

    function _getForkRpc() internal view override returns (string memory) {
        return vm.envString("BASE_MAINNET_RPC_URL");
    }
}

// contract EzEthHandler_WithRateChange_ForkTest is EzEthWethHandler_ForkTest {
//     function setUp() public virtual override {
//         super.setUp();

//         ionPool.setRate(ILK_INDEX, 3.5708923502395e27);
//     }
// }
