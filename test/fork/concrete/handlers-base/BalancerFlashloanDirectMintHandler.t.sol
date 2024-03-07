// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { LstHandler_ForkBase } from "../../../helpers/handlers/LstHandlerForkBase.sol";
import { WadRayMath, RAY } from "../../../../src/libraries/math/WadRayMath.sol";
import { BalancerFlashloanDirectMintHandler, VAULT } from "../../../../src/flash/BalancerFlashloanDirectMintHandler.sol";
import { Whitelist } from "../../../../src/Whitelist.sol";

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

import { IFlashLoanRecipient } from "@balancer-labs/v2-interfaces/contracts/vault/IFlashLoanRecipient.sol";
import { IERC20 as IERC20Balancer } from "@balancer-labs/v2-interfaces/contracts/vault/IVault.sol";

import { console2 } from "forge-std/console2.sol";

using WadRayMath for uint256;

abstract contract BalancerFlashloanDirectMintHandler_Test is LstHandler_ForkBase {
    function testFork_FlashloanCollateral() public virtual {
        uint256 initialDeposit = 1e18;
        uint256 resultingAdditionalCollateral = 5e18;
        uint256 maxResultingDebt =
            _getProviderLibrary().getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        weth.approve(address(_getTypedBFDMHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedBFDMHandler()));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            _getTypedBFDMHandler().flashLeverageCollateral(
                initialDeposit, resultingAdditionalCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        uint256 gasBefore = gasleft();
        _getTypedBFDMHandler().flashLeverageCollateral(
            initialDeposit, resultingAdditionalCollateral, maxResultingDebt, borrowerWhitelistProof
        );
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;
        if (currentRate % RAY != 0) roundingError++;

        assertLe(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulUp(ionPool.rate(_getIlkIndex())),
            maxResultingDebt + roundingError
        );
        assertEq(IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedBFDMHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedBFDMHandler())), roundingError);
        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingAdditionalCollateral);
    }

    function testFork_FlashloanWeth() external {
        uint256 initialDeposit = 1e18; // in ethX
        uint256 resultingAdditionalCollateral = 5e18; // in ethX
        uint256 maxResultingDebt =
            _getProviderLibrary().getEthAmountInForLstAmountOut(resultingAdditionalCollateral - initialDeposit);

        weth.approve(address(_getTypedBFDMHandler()), type(uint256).max);
        ionPool.addOperator(address(_getTypedBFDMHandler()));

        if (Whitelist(whitelist).borrowersRoot(0) != 0) {
            vm.expectRevert(abi.encodeWithSelector(Whitelist.NotWhitelistedBorrower.selector, 0, address(this)));
            _getTypedBFDMHandler().flashLeverageWeth(
                initialDeposit, resultingAdditionalCollateral, maxResultingDebt, new bytes32[](0)
            );
        }

        uint256 gasBefore = gasleft();
        _getTypedBFDMHandler().flashLeverageWeth(
            initialDeposit, resultingAdditionalCollateral, maxResultingDebt, borrowerWhitelistProof
        );
        uint256 gasAfter = gasleft();
        if (vm.envOr("SHOW_GAS", uint256(0)) == 1) console2.log("Gas used: %d", gasBefore - gasAfter);

        uint256 currentRate = ionPool.rate(_getIlkIndex());
        uint256 roundingError = currentRate / RAY;

        assertApproxEqAbs(
            ionPool.normalizedDebt(_getIlkIndex(), address(this)).rayMulDown(ionPool.rate(_getIlkIndex())),
            maxResultingDebt,
            roundingError
        );
        assertEq(IERC20(address(_getCollaterals()[_getIlkIndex()])).balanceOf(address(_getTypedBFDMHandler())), 0);
        assertLe(weth.balanceOf(address(_getTypedBFDMHandler())), roundingError);
        assertEq(ionPool.collateral(_getIlkIndex(), address(this)), resultingAdditionalCollateral);
    }

    function testFork_RevertWhen_BalancerFlashloanNotInitiatedByHandler() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(_getCollaterals()[_getIlkIndex()]));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalBalancerFlashloanNotAllowed.selector);
        VAULT.flashLoan(
            IFlashLoanRecipient(address(_getTypedBFDMHandler())), addresses, amounts, abi.encode(msg.sender, 0, 0, 0)
        );
    }

    function testFork_RevertWhen_BalancerFlashloanedMoreThanOneToken() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        IERC20Balancer[] memory addresses = new IERC20Balancer[](2);

        address collateral = address(_getCollaterals()[_getIlkIndex()]);
        address wethAddress = address(weth);

        addresses[0] = IERC20Balancer(collateral);
        addresses[1] = IERC20Balancer(wethAddress);

        if (collateral > wethAddress) {
            addresses[0] = IERC20Balancer(wethAddress);
            addresses[1] = IERC20Balancer(collateral);
        }

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 8e18;
        amounts[1] = 8e18;

        vm.expectRevert(abi.encodeWithSelector(BalancerFlashloanDirectMintHandler.FlashLoanedTooManyTokens.selector, 2));
        VAULT.flashLoan(
            IFlashLoanRecipient(address(_getTypedBFDMHandler())), addresses, amounts, abi.encode(msg.sender, 0, 0, 0)
        );
    }

    function testFork_RevertWhen_UntrustedCallerCallsBalancerFlashloanCallback() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(_getCollaterals()[_getIlkIndex()]));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        vm.expectRevert(
            abi.encodeWithSelector(BalancerFlashloanDirectMintHandler.ReceiveCallerNotVault.selector, address(this))
        );
        _getTypedBFDMHandler().receiveFlashLoan(addresses, amounts, amounts, "");
    }

    function testFork_RevertWhen_FlashloanedTokenIsNeitherWethNorCorrectLst() external {
        vm.skip(borrowerWhitelistProof.length > 0);

        IERC20Balancer[] memory addresses = new IERC20Balancer[](1);
        addresses[0] = IERC20Balancer(address(_getCollaterals()[_getIlkIndex()]));

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 8e18;

        // Should actually be impossible
        vm.expectRevert(BalancerFlashloanDirectMintHandler.ExternalBalancerFlashloanNotAllowed.selector);
        vm.prank(address(VAULT));
        _getTypedBFDMHandler().receiveFlashLoan(
            addresses, amounts, amounts, abi.encode(address(this), 100e18, 100e18, 100e18)
        );
    }

    function _getTypedBFDMHandler() private view returns (BalancerFlashloanDirectMintHandler) {
        return BalancerFlashloanDirectMintHandler(payable(_getHandler()));
    }
}
