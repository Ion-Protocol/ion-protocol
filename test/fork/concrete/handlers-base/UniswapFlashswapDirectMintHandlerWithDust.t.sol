// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { UniswapFlashswapDirectMintHandlerWithDust } from
    "../../../../src/flash/UniswapFlashswapDirectMintHandlerWithDust.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";
import { LrtHandler_ForkBase } from "../../../helpers/handlers/LrtHandlerForkBase.sol";
import { WadRayMath, RAY } from "../../../../src/libraries/math/WadRayMath.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { console2 } from "forge-std/console2.sol";

using WadRayMath for uint256;

abstract contract UniswapFlashswapDirectMintHandlerWithDust_Test is LrtHandler_ForkBase {
    function testFork_FlashswapAndMint() public virtual {
        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5.239573295673902613e18;
        uint256 maxResultingDebt =
            _getProviderLibrary().getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        weth.approve(address(_getTypedUFDMHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFDMHandler()));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            _getTypedUFDMHandler().flashswapAndMint(
                initialDeposit, resultingAdditionalCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
            );
        }

        uint256 gasBefore = gasleft();
        _getTypedUFDMHandler().flashswapAndMint(
            initialDeposit, resultingAdditionalCollateral, maxResultingDebt, block.timestamp + 1, borrowerWhitelistProof
        );
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;
        if (currentRate % RAY != 0) roundingError++;

        assertLe(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt + roundingError,
            "max resulting debt upper bound with rounding error"
        );
        assertEq(
            IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedUFDMHandler())),
            0,
            "collateral balanceOf"
        );
        assertLe(IERC20(_getUnderlying()).balanceOf(address(_getTypedUFDMHandler())), roundingError, "rounding error");
        // TODO: bound this with a max dust bound
        assertGt(
            ionPool.collateral(_getIlkIndex(), address(this)),
            resultingAdditionalCollateral,
            "resulting collateral should be greater than the expected collateral accounting for dust"
        );
    }

    function testFork_RevertWhen_UntrustedCallerCallsFlashswapCallback() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                UniswapFlashswapDirectMintHandlerWithDust.CallbackOnlyCallableByPool.selector, address(this)
            )
        );
        _getTypedUFDMHandler().uniswapV3SwapCallback(1, 1, "");
    }

    function testFork_RevertWhen_FlashswapAndMintCreatesMoreDebtThanUserIsWilling() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt = 3e18; // In weth

        weth.approve(address(_getTypedUFDMHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedUFDMHandler()));

        vm.expectRevert();
        _getTypedUFDMHandler().flashswapAndMint(
            initialDeposit, resultingAdditionalCollateral, maxResultingDebt, block.timestamp + 1, new bytes32[](0)
        );
    }

    function _getTypedUFDMHandler() internal view returns (UniswapFlashswapDirectMintHandlerWithDust) {
        return UniswapFlashswapDirectMintHandlerWithDust(payable(_getHandler()));
    }
}
