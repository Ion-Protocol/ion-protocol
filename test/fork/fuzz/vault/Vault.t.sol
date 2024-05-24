// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { VaultForkBase } from "./../../../helpers/VaultForkSharedSetup.sol";

contract Vault_ForkFuzzTest is VaultForkBase {
    function test_Deposit_BelowMaxDeposit_Withdraw_BelowMaxWithdraw(uint256 assets) public {
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        uint256 maxDeposit = vault.maxDeposit(NULL);
        require(maxDeposit > 0, "max deposit");

        uint256 depositAmt = bound(assets, 0, maxDeposit);

        uint256 expectedSharesMinted = vault.previewDeposit(depositAmt);

        deal(address(BASE_ASSET), address(this), depositAmt);
        BASE_ASSET.approve(address(vault), depositAmt);

        uint256 resultingSharesMinted = vault.deposit(depositAmt, address(this));

        uint256 totalAssetsAfterDeposit = vault.totalAssets();
        uint256 totalSupplyAfterDeposit = vault.totalSupply();

        // user
        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "requested assets deposited");
        assertEq(resultingSharesMinted, expectedSharesMinted, "shares minted");
        assertEq(vault.balanceOf(address(this)), resultingSharesMinted, "vault shares");

        // vault
        assertEq(resultingSharesMinted, totalSupplyAfterDeposit - totalSupply, "vault total supply after deposit");
        assertApproxEqAbs(depositAmt, totalAssetsAfterDeposit - totalAssets, 3, "vault total assets after deposit"); // 1
            // wei error per market

        // tries to withdraw max
        uint256 maxWithdraw = vault.maxWithdraw(address(this));
        uint256 withdrawAmt = bound(assets, 0, maxWithdraw);

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
            withdrawAmt, totalAssetsAfterDeposit - totalAssetsAfterWithdraw, 1, "total assets after withdraw"
        );
    }

    function test_Mint_BelowMaxMint_Redeem_BelowMaxRedeem(uint256 assets) public {
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        uint256 maxMint = vault.maxMint(NULL);
        require(maxMint > 0, "max mint");

        uint256 mintAmt = bound(assets, 0, maxMint);

        uint256 expectedAssetsDeposited = vault.previewMint(mintAmt);

        deal(address(BASE_ASSET), address(this), expectedAssetsDeposited);
        BASE_ASSET.approve(address(vault), expectedAssetsDeposited);

        uint256 resultingAssetsDeposited = vault.mint(mintAmt, address(this));

        uint256 totalAssetsAfterMint = vault.totalAssets();
        uint256 totalSupplyAfterMint = vault.totalSupply();

        // user
        assertEq(BASE_ASSET.balanceOf(address(this)), 0, "requested assets deposited");
        assertEq(resultingAssetsDeposited, expectedAssetsDeposited, "assets deposited");
        assertEq(vault.balanceOf(address(this)), mintAmt, "vault shares");

        // vault
        assertEq(mintAmt, totalSupplyAfterMint - totalSupply, "vault total supply after deposit");
        assertApproxEqAbs(
            resultingAssetsDeposited, totalAssetsAfterMint - totalAssets, 3, "vault total assets after deposit"
        ); // 1 wei error per market

        uint256 prevShares = vault.balanceOf(address(this));

        uint256 maxRedeem = vault.maxRedeem(address(this));
        uint256 redeemAmt = bound(assets, 0, maxRedeem);

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
