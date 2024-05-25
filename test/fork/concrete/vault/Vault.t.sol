// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Vault } from "./../../../../src/vault/Vault.sol";

import { VaultForkBase } from "./../../../helpers/VaultForkSharedSetup.sol";

contract Vault_ForkTest is VaultForkBase {
    function test_Deposit_MaxDeposit_MaxWithdraw() public {
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        uint256 maxDeposit = vault.maxDeposit(NULL);
        require(maxDeposit > 0, "max deposit");

        uint256 expectedSharesMinted = vault.previewDeposit(maxDeposit);

        deal(address(BASE_ASSET), address(this), maxDeposit);
        BASE_ASSET.approve(address(vault), maxDeposit);

        uint256 resultingSharesMinted = vault.deposit(maxDeposit, address(this));

        uint256 totalAssetsAfterDeposit = vault.totalAssets();
        uint256 totalSupplyAfterDeposit = vault.totalSupply();

        // user
        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "requested assets deposited");
        assertEq(resultingSharesMinted, expectedSharesMinted, "shares minted");
        assertEq(vault.balanceOf(address(this)), resultingSharesMinted, "vault shares");

        // vault
        assertEq(resultingSharesMinted, totalSupplyAfterDeposit - totalSupply, "vault total supply after deposit");
        assertApproxEqAbs(maxDeposit, totalAssetsAfterDeposit - totalAssets, 4, "vault total assets after deposit"); // 1
            // wei error per market

        uint256 withdrawAmt = vault.maxWithdraw(address(this));

        uint256 expectedSharesRedeemed = vault.previewWithdraw(withdrawAmt);
        uint256 resultingSharesRedeemed = vault.withdraw(withdrawAmt, address(this), address(this));

        uint256 totalAssetsAfterWithdraw = vault.totalAssets();
        uint256 totalSupplyAfterWithdraw = vault.totalSupply();

        // user
        assertEq(BASE_ASSET.balanceOf(address(this)), withdrawAmt, "requested assets withdrawn");
        assertEq(resultingSharesRedeemed, expectedSharesRedeemed, "shares redeemed");

        // vault
        assertEq(
            resultingSharesRedeemed, totalSupplyAfterDeposit - totalSupplyAfterWithdraw, "total supply after withdraw"
        );
        assertApproxEqAbs(
            withdrawAmt, totalAssetsAfterDeposit - totalAssetsAfterWithdraw, 3, "total assets after withdraw"
        );
    }

    function test_Deposit_MaxMint_MaxRedeem() public {
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        uint256 maxMint = vault.maxMint(NULL);
        require(maxMint > 0, "max mint");

        uint256 expectedAssetsDeposited = vault.previewMint(maxMint);

        deal(address(BASE_ASSET), address(this), expectedAssetsDeposited);
        BASE_ASSET.approve(address(vault), expectedAssetsDeposited);

        uint256 resultingAssetsDeposited = vault.mint(maxMint, address(this));

        uint256 totalAssetsAfterMint = vault.totalAssets();
        uint256 totalSupplyAfterMint = vault.totalSupply();

        // user
        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "requested assets deposited");
        assertEq(resultingAssetsDeposited, expectedAssetsDeposited, "assets deposited");
        assertEq(vault.balanceOf(address(this)), maxMint, "vault shares");

        // vault
        assertEq(maxMint, totalSupplyAfterMint - totalSupply, "vault total supply after deposit");
        assertApproxEqAbs(
            resultingAssetsDeposited, totalAssetsAfterMint - totalAssets, 4, "vault total assets after deposit"
        ); // 1 wei error per market

        uint256 prevShares = vault.balanceOf(address(this));

        uint256 redeemAmt = vault.maxRedeem(address(this));
        uint256 expectedWithdrawAmt = vault.previewRedeem(redeemAmt);
        uint256 resultingWithdrawAmt = vault.redeem(redeemAmt, address(this), address(this));

        uint256 totalAssetsAfterRedeem = vault.totalAssets();
        uint256 totalSupplyAfterRedeem = vault.totalSupply();
        uint256 sharesDiff = prevShares - vault.balanceOf(address(this));

        // user
        assertEq(BASE_ASSET.balanceOf(address(this)), expectedWithdrawAmt, "requested assets withdrawn");
        assertEq(resultingWithdrawAmt, expectedWithdrawAmt, "withdraw amount");
        assertEq(sharesDiff, redeemAmt, "redeem amount");

        // vault
        assertEq(redeemAmt, totalSupplyAfterMint - totalSupplyAfterRedeem, "total supply after withdraw");
        assertApproxEqAbs(
            expectedWithdrawAmt, totalAssetsAfterMint - totalAssetsAfterRedeem, 1, "total assets after withdraw"
        );
    }
}
