// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { L1BasicWithdrawal } from "../../../../src/vault/L1BasicWithdrawal.sol";
import { IConnext } from "../../../../src/interfaces/IConnext.sol";
import { IVault } from "../../../../src/interfaces/IVault.sol";
import { IIonPool } from "../../../../src/interfaces/IIonPool.sol";

import { VaultSharedSetup } from "../../../helpers/VaultSharedSetup.sol";
import { XERC20 } from "../../../helpers/XERC20.sol";
import { XERC20Lockbox } from "../../../helpers/XERC20Lockbox.sol";
import { ERC20PresetMinterPauser } from "../../../helpers/ERC20PresetMinterPauser.sol";

contract L1BasicMintTest is VaultSharedSetup {
    IConnext internal constant L1_CONNEXT = IConnext(0x8898B472C54c31894e3B9bb83cEA802a5d0e63C6);

    XERC20 xErc20;
    XERC20Lockbox lockbox;
    L1BasicWithdrawal l1BasicWithdrawal;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        super.setUp();
        xErc20 = new XERC20({ _name: "xErc20", _symbol: "XERC20", _factory: address(this) });
        lockbox = new XERC20Lockbox({ _xerc20: address(xErc20), _erc20: address(vault), _isNative: false });
        l1BasicWithdrawal = new L1BasicWithdrawal({ _connext: address(L1_CONNEXT) });

        xErc20.setLockbox(address(lockbox));
        xErc20.setLimits(address(L1_CONNEXT), 100e18, 100e18);

        uint256[] memory allocationCaps = new uint256[](3);
        allocationCaps[0] = 100e18;
        allocationCaps[1] = 100e18;
        allocationCaps[2] = 100e18;

        IIonPool[] memory marketsToRemove = new IIonPool[](3);
        marketsToRemove[0] = weEthIonPool;
        marketsToRemove[1] = rsEthIonPool;
        marketsToRemove[2] = rswEthIonPool;

        vm.prank(OWNER);
        vault.updateAllocationCaps(marketsToRemove, allocationCaps);

        deal(address(vault.BASE_ASSET()), address(this), 100e18);
    }

    function test_xReceiveFail() public {
        vault.deposit(50e18, address(this));

        bytes32 mockTransferId = bytes32(0);
        uint256 amount = 1000;
        address fallbackAddress = makeAddr("fallback");
        address receiver = makeAddr("receiver");

        bytes memory data = abi.encode(vault, lockbox, xErc20, receiver);
        bytes memory calldata_ = abi.encode(fallbackAddress, data);

        deal(address(xErc20), address(this), amount);
        xErc20.transfer(address(l1BasicWithdrawal), amount);

        vm.prank(address(L1_CONNEXT));
        l1BasicWithdrawal.xReceive(mockTransferId, amount, address(xErc20), address(0), uint32(0), calldata_);

        assertEq(vault.balanceOf(address(this)), 50e18);
        assertEq(xErc20.balanceOf(fallbackAddress), amount);
    }

    function test_xReceive() public {
        deal(address(vault), address(this), 100e18);
        vault.approve(address(lockbox), type(uint256).max);
        lockbox.deposit(100e18);

        vault.deposit(50e18, address(this));

        bytes32 mockTransferId = bytes32(0);
        uint256 amount = 1000;
        address fallbackAddress = makeAddr("fallback");
        address receiver = makeAddr("receiver");

        bytes memory data = abi.encode(vault, lockbox, xErc20, receiver);
        bytes memory calldata_ = abi.encode(fallbackAddress, data);

        xErc20.transfer(address(l1BasicWithdrawal), amount);

        vm.prank(address(L1_CONNEXT));
        l1BasicWithdrawal.xReceive(mockTransferId, amount, address(xErc20), address(0), uint32(0), calldata_);

        assertEq(vault.balanceOf(address(this)), 50e18);
        assertEq(vault.BASE_ASSET().balanceOf(fallbackAddress), 0);
        assertEq(vault.BASE_ASSET().balanceOf(receiver), amount);
    }
}
