// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { VaultSharedSetup } from "../../../helpers/VaultSharedSetup.sol";

import { console2 } from "forge-std/console2.sol";

contract Vault_WithYieldAndFee is VaultSharedSetup {
    uint256 constant INITIAL_SUPPLY_AMT = 1000e18;

    function setUp() public virtual override {
        super.setUp();

        weEthIonPool.updateSupplyCap(type(uint256).max);
        rsEthIonPool.updateSupplyCap(type(uint256).max);
        rswEthIonPool.updateSupplyCap(type(uint256).max);

        weEthIonPool.updateIlkDebtCeiling(0, type(uint256).max);
        rsEthIonPool.updateIlkDebtCeiling(0, type(uint256).max);
        rswEthIonPool.updateIlkDebtCeiling(0, type(uint256).max);

        supply(address(this), weEthIonPool, INITIAL_SUPPLY_AMT);
        borrow(address(this), weEthIonPool, weEthGemJoin, 100e18, 70e18);

        supply(address(this), rsEthIonPool, INITIAL_SUPPLY_AMT);
        borrow(address(this), rsEthIonPool, rsEthGemJoin, 100e18, 70e18);

        supply(address(this), rswEthIonPool, INITIAL_SUPPLY_AMT);
        borrow(address(this), rswEthIonPool, rswEthGemJoin, 100e18, 70e18);
    }

    function test_AccrueYieldSingleMarket() public {
        // When yield is accrued,
        // the total assets increases,
        // the vault shares should stay the same.

        uint256 depositAmount = 100e18;
        setERC20Balance(address(BASE_ASSET), address(this), depositAmount);

        updateSupplyQueue(vault, weEthIonPool, rsEthIonPool, rswEthIonPool);
        updateSupplyCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);
        updateAllocationCaps(vault, type(uint256).max, type(uint256).max, type(uint256).max);

        vault.deposit(depositAmount, address(this));

        // before yield accrual
        uint256 prevTotalAssets = vault.totalAssets();
        uint256 prevWeEthIonPoolClaim = weEthIonPool.getUnderlyingClaimOf(address(vault));

        vm.warp(block.timestamp + 365 days);

        (uint256 totalSupplyFactorIncrease,,,,) = weEthIonPool.calculateRewardAndDebtDistribution();
        console2.log("totalSupplyFactorIncrease: ", totalSupplyFactorIncrease);
        assertGt(totalSupplyFactorIncrease, 0, "total supply factor increase");

        weEthIonPool.accrueInterest();

        // after yield accrual
        uint256 newTotalAssets = vault.totalAssets();
        uint256 newWeEthIonPoolClaim = weEthIonPool.getUnderlyingClaimOf(address(vault));

        console2.log("prevTotalAssets: ", prevTotalAssets);
        console2.log("newTotalAssets: ", newTotalAssets);

        // ionPool
        assertEq(
            newTotalAssets - prevTotalAssets, newWeEthIonPoolClaim - prevTotalAssets, "yield accrual to total assets"
        );

        // vault

        // users
    }

    function test_AccrueYieldAllMarkets() public { }

    function test_WithFee_AccrueYieldSingleMarket() public { }

    function test_WithFee_AccrueYieldAllMarkets() public { }
}

contract Vault_WithRate_WithYieldAndFee is Vault_WithYieldAndFee {
    function setUp() public override {
        super.setUp();
    }
}
