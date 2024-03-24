// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IWstEth } from "../../../../src/interfaces/ProviderInterfaces.sol";
import { WstEthHandler } from "../../../../src/flash/lst/WstEthHandler.sol";
import { WadRayMath, RAY } from "../../../../src/libraries/math/WadRayMath.sol";
import { LidoLibrary } from "../../../../src/libraries/lst/LidoLibrary.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";
import { IonHandlerBase } from "../../../../src/flash/IonHandlerBase.sol";

import { BalancerFlashloanDirectMintHandler_Test } from "../handlers-base/BalancerFlashloanDirectMintHandler.t.sol";
import { UniswapFlashswapHandler_Test } from "../handlers-base/UniswapFlashswapHandler.t.sol";
import { LstHandler_ForkBase } from "../../../helpers/handlers/LstHandlerForkBase.sol";
import { IProviderLibraryExposed } from "../../../helpers/IProviderLibraryExposed.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

using WadRayMath for uint256;
using WadRayMath for uint104;
using LidoLibrary for IWstEth;

contract LidoLibraryExposed is IProviderLibraryExposed {
    IWstEth wstEth;

    constructor(IWstEth wstEth_) {
        wstEth = wstEth_;
    }

    function getEthAmountInForLstAmountOut(uint256 lstAmount) external view returns (uint256) {
        return wstEth.getEthAmountInForLstAmountOut(lstAmount);
    }

    function getLstAmountOutForEthAmountIn(uint256 ethAmount) external view returns (uint256) {
        return wstEth.getLstAmountOutForEthAmountIn(ethAmount);
    }
}

abstract contract WstEthHandler_ForkBase is LstHandler_ForkBase {
    uint8 internal constant ilkIndex = 0;
    WstEthHandler wstEthHandler;
    IProviderLibraryExposed providerLibrary;

    function setUp() public virtual override {
        super.setUp();

        wstEthHandler = new WstEthHandler(ilkIndex, ionPool, gemJoins[ilkIndex], Whitelist(whitelist), WSTETH_WETH_POOL);

        IERC20(address(MAINNET_WSTETH)).approve(address(wstEthHandler), type(uint256).max);

        // Remove debt ceiling for this test
        for (uint8 i = 0; i < lens.ilkCount(iIonPool); i++) {
            ionPool.updateIlkDebtCeiling(i, type(uint256).max);
        }

        providerLibrary = new LidoLibraryExposed(MAINNET_WSTETH);

        vm.deal(address(this), INITIAL_BORROWER_COLLATERAL_BALANCE);
        MAINNET_WSTETH.depositForLst(INITIAL_BORROWER_COLLATERAL_BALANCE);
    }

    function _mintStEth(uint256 amount) internal returns (uint256) {
        uint256 beginningBalance = IERC20(address(MAINNET_STETH)).balanceOf(address(this));
        vm.deal(address(this), amount);
        (bool sent,) = address(MAINNET_STETH).call{ value: amount }("");
        require(sent == true, "mint stEth failed");
        uint256 resultingBalance = IERC20(address(MAINNET_STETH)).balanceOf(address(this));
        return resultingBalance - beginningBalance;
    }

    function _getIlkIndex() internal pure override returns (uint8) {
        return ilkIndex;
    }

    function _getProviderLibrary() internal view override returns (IProviderLibraryExposed) {
        return providerLibrary;
    }

    function _getHandler() internal view override returns (address) {
        return address(wstEthHandler);
    }
}

contract WstEthHandler_ForkTest is
    WstEthHandler_ForkBase,
    BalancerFlashloanDirectMintHandler_Test,
    UniswapFlashswapHandler_Test
{
    function setUp() public virtual override(WstEthHandler_ForkBase, LstHandler_ForkBase) {
        super.setUp();

        // If price of the pool ends up being larger than the exchange rate,
        // then a direct 1:1 contract mint is more favorable
        uint256 exchangeRate = MAINNET_WSTETH.getStETHByWstETH(1 ether);
        sqrtPriceLimitX96 = uint160(Math.sqrt(uint256(exchangeRate << 192) / 1e18));
    }
}

contract WstEthHandler_Zap_ForkTest is WstEthHandler_ForkBase {
    function testFork_ZapDepositAndBorrow() external {
        uint256 ethDepositAmount = 2e18; // in eth
        uint256 borrowAmount = 0.5e18; // in weth

        uint256 stEthDepositAmount = _mintStEth(ethDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);
        ionPool.addOperator(address(wstEthHandler));

        // if whitelist root is not zero, check that incorrect merkle proof fails
        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapDepositAndBorrow(stEthDepositAmount, borrowAmount, new bytes32[](0));
        }

        wstEthHandler.zapDepositAndBorrow(stEthDepositAmount, borrowAmount, borrowerWhitelistProof);

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        uint256 expectedWstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount); // in wstEth

        assertEq(ionPool.collateral(ilkIndex, address(this)), expectedWstEthDepositAmount);
        assertEq(ionPool.normalizedDebt(ilkIndex, address(this)), borrowAmount.rayDivUp(currentRate));
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0);
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError);
    }

    function testFork_ZapFlashLeverageCollateralZeroInitialDeposit() external {
        ionPool.addOperator(address(wstEthHandler));

        // first create a position
        uint256 ethDepositAndBorrowDepositAmount = 10e18;
        uint256 borrowAmount = 0e18;

        uint256 initialStEthDepositAmount = _mintStEth(ethDepositAndBorrowDepositAmount);
        uint256 startingWstEthDepositAmount =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(initialStEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), initialStEthDepositAmount);
        wstEthHandler.zapDepositAndBorrow(initialStEthDepositAmount, borrowAmount, borrowerWhitelistProof);

        // flash leverage inputs
        uint256 stEthDepositAmount = 0;
        uint256 resultingAdditionalStEthCollateral = 5e18;

        // expected inputs
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapFlashLeverageCollateral(
                stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        wstEthHandler.zapFlashLeverageCollateral(
            stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(
            ionPool.collateral(ilkIndex, address(this)),
            startingWstEthDepositAmount + resultingAdditionalWstEthCollateral,
            "collateral"
        );
        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "resulting debt lower than max resulting debt"
        );
        assertEq(
            IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)),
            0,
            "handler resulting wstEth balance is zero"
        );
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
    }

    function testFork_ZapFlashLeverageCollateral() external {
        uint256 ethDepositAmount = 2e18; // in eth

        // input to zap
        uint256 stEthDepositAmount = _mintStEth(ethDepositAmount);
        uint256 resultingAdditionalStEthCollateral = 5e18; // in stEth

        // expected input to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapFlashLeverageCollateral(
                stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        wstEthHandler.zapFlashLeverageCollateral(
            stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalWstEthCollateral, "collateral");
    }

    function testFork_ZapFlashLeverageWethZeroInitialDeposit() external {
        ionPool.addOperator(address(wstEthHandler));

        // first create a position
        uint256 ethDepositAndBorrowDepositAmount = 10e18;
        uint256 borrowAmount = 0e18;

        uint256 initialStEthDepositAmount = _mintStEth(ethDepositAndBorrowDepositAmount);
        uint256 startingWstEthDepositAmount =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(initialStEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), initialStEthDepositAmount);
        wstEthHandler.zapDepositAndBorrow(initialStEthDepositAmount, borrowAmount, borrowerWhitelistProof);

        // flash leverage with zero initial deposit param
        uint256 stEthDepositAmount = 0;
        uint256 resultingAdditionalStEthCollateral = 7e18; // in stEth

        // expected input to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);

        wstEthHandler.zapFlashLeverageWeth(
            stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(
            ionPool.collateral(ilkIndex, address(this)),
            startingWstEthDepositAmount + resultingAdditionalWstEthCollateral,
            "collateral"
        );
        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
    }

    function testFork_ZapFlashLeverageWeth() external {
        uint256 ethDepositAmount = 5e18; // in eth

        // input to zap
        uint256 stEthDepositAmount = _mintStEth(ethDepositAmount);
        uint256 resultingAdditionalStEthCollateral = 7e18; // in stEth

        // expected input to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt =
            MAINNET_WSTETH.getEthAmountInForLstAmountOut(resultingAdditionalWstEthCollateral - wstEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapFlashLeverageWeth(
                stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        wstEthHandler.zapFlashLeverageWeth(
            stEthDepositAmount, resultingAdditionalStEthCollateral, maxResultingDebt, borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalWstEthCollateral, "collateral");
    }

    function testFork_ZapFlashswapLeverageZeroInitialDeposit() external {
        ionPool.addOperator(address(wstEthHandler));

        // first create a position
        uint256 ethDepositAndBorrowDepositAmount = 10e18;
        uint256 borrowAmount = 0e18;

        uint256 initialStEthDepositAmount = _mintStEth(ethDepositAndBorrowDepositAmount);
        uint256 startingWstEthDepositAmount =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(initialStEthDepositAmount);

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), initialStEthDepositAmount);
        wstEthHandler.zapDepositAndBorrow(initialStEthDepositAmount, borrowAmount, borrowerWhitelistProof);

        // flashswap with zero initial deposit param
        uint256 stEthDepositAmount = 0;
        uint256 resultingAdditionalStEthCollateral = 4.6e18;

        // expected inputs to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt = MAINNET_WSTETH.getEthAmountInForLstAmountOut(
            resultingAdditionalWstEthCollateral - wstEthDepositAmount
        ) * 1.005e18; // Some slippage tolerance
        uint160 sqrtPriceLimitX96 = 0;

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);

        vm.expectRevert(abi.encodeWithSelector(IonHandlerBase.TransactionDeadlineReached.selector, block.timestamp));
        wstEthHandler.zapFlashswapLeverage(
            stEthDepositAmount,
            resultingAdditionalStEthCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp,
            borrowerWhitelistProof
        );

        wstEthHandler.zapFlashswapLeverage(
            stEthDepositAmount,
            resultingAdditionalStEthCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertEq(
            ionPool.collateral(ilkIndex, address(this)),
            startingWstEthDepositAmount + resultingAdditionalWstEthCollateral,
            "collateral"
        );
        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
    }

    function testFork_ZapFlashswapLeverage() external {
        uint256 ethDepositAmount = 1.4e18;

        // input to zap
        uint256 stEthDepositAmount = _mintStEth(ethDepositAmount);
        uint256 resultingAdditionalStEthCollateral = 2.8e18;

        // expected inputs to flashLeverageCollateral
        uint256 wstEthDepositAmount = MAINNET_WSTETH.getWstETHByStETH(stEthDepositAmount);
        uint256 resultingAdditionalWstEthCollateral =
            IWstEth(address(MAINNET_WSTETH)).getWstETHByStETH(resultingAdditionalStEthCollateral);

        uint256 maxResultingDebt = MAINNET_WSTETH.getEthAmountInForLstAmountOut(
            resultingAdditionalWstEthCollateral - wstEthDepositAmount
        ) * 1.005e18; // Some slippage tolerance
        uint160 sqrtPriceLimitX96 = 0;

        IERC20(address(MAINNET_STETH)).approve(address(wstEthHandler), stEthDepositAmount);
        ionPool.addOperator(address(wstEthHandler));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            wstEthHandler.zapFlashswapLeverage(
                stEthDepositAmount,
                resultingAdditionalStEthCollateral,
                maxResultingDebt,
                sqrtPriceLimitX96,
                block.timestamp + 1,
                new bytes32[](0)
            );
        }

        vm.expectRevert(abi.encodeWithSelector(IonHandlerBase.TransactionDeadlineReached.selector, block.timestamp));
        wstEthHandler.zapFlashswapLeverage(
            stEthDepositAmount,
            resultingAdditionalStEthCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp,
            borrowerWhitelistProof
        );

        wstEthHandler.zapFlashswapLeverage(
            stEthDepositAmount,
            resultingAdditionalStEthCollateral,
            maxResultingDebt,
            sqrtPriceLimitX96,
            block.timestamp + 1,
            borrowerWhitelistProof
        );

        uint256 currentRate = ionPool.rate(ilkIndex);
        uint256 roundingError = currentRate / RAY;

        assertLe(
            ionPool.normalizedDebt(ilkIndex, address(this)).rayMulUp(ionPool.rate(ilkIndex)),
            maxResultingDebt,
            "max resulting debt"
        );
        assertEq(IERC20(address(MAINNET_WSTETH)).balanceOf(address(wstEthHandler)), 0, "handler wstEth balance");
        assertLe(weth.balanceOf(address(wstEthHandler)), roundingError, "handler weth dust");
        assertEq(ionPool.collateral(ilkIndex, address(this)), resultingAdditionalWstEthCollateral, "collateral");
    }
}

contract WstEthHandlerWhitelist_ForkTest is WstEthHandler_ForkTest, WstEthHandler_Zap_ForkTest {
    // generate merkle root
    // ["0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496"],
    // ["0x2222222222222222222222222222222222222222"],
    // => 0xb51a382d5bcb4cd5fe50a7d4d8abaf056ac1a6961cf654ec4f53a570ab75a30b

    bytes32 borrowerWhitelistRoot = 0x846dfddafc70174f2089edda6408bf9dd643c19ee06ff11643b614f0e277d6e3;

    bytes32[][] borrowerProofs = [
        [bytes32(0x708e7cb9a75ffb24191120fba1c3001faa9078147150c6f2747569edbadee751)],
        [bytes32(0xa6e6806303186f9c20e1af933c7efa83d98470acf93a10fb8da8b1d9c2873640)]
    ];

    function setUp() public override(WstEthHandler_ForkBase, WstEthHandler_ForkTest) {
        super.setUp();

        bytes32[] memory borrowerRoots = new bytes32[](1);
        borrowerRoots[0] = borrowerWhitelistRoot;

        // update current whitelist with a new borrower root
        Whitelist _whitelist = Whitelist(lens.whitelist(iIonPool));
        _whitelist.updateBorrowersRoot(ilkIndex, borrowerWhitelistRoot);
        _whitelist.approveProtocolWhitelist(address(wstEthHandler));

        borrowerWhitelistProof = borrowerProofs[0];
    }
}

contract WstEthHandler_WithRateChange_ForkTest is WstEthHandler_ForkTest {
    function setUp() public virtual override {
        super.setUp();

        ionPool.setRate(ilkIndex, 3.5708923502395e27);
    }
}
