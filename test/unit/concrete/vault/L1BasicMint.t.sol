// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { L1BasicMint } from "../../../../src/vault/L1BasicMint.sol";
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
    L1BasicMint l1BasicMint;

    function setUp() public override {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        super.setUp();
        xErc20 = new XERC20({ _name: "xErc20", _symbol: "XERC20", _factory: address(this) });
        lockbox = new XERC20Lockbox({ _xerc20: address(xErc20), _erc20: address(vault), _isNative: false });
        l1BasicMint = new L1BasicMint({ _connext: L1_CONNEXT });

        xErc20.setLockbox(address(lockbox));
        xErc20.setLimits(address(L1_CONNEXT), 100e18, 100e18);

        uint256[] memory allocationCaps = new uint256[](3);
        allocationCaps[0] = 1e18;
        allocationCaps[1] = 1e18;
        allocationCaps[2] = 1e18;

        IIonPool[] memory marketsToRemove = new IIonPool[](3);
        marketsToRemove[0] = weEthIonPool;
        marketsToRemove[1] = rsEthIonPool;
        marketsToRemove[2] = rswEthIonPool;

        vm.prank(OWNER);
        vault.updateAllocationCaps(marketsToRemove, allocationCaps);
    }

    function test_depositAndXCall() public {
        uint256 amountOfBase = 1000;
        uint32 destination = 1_836_016_741; // Mode
        address to = address(this);
        uint256 slippage = 0;

        deal(address(vault.BASE_ASSET()), address(this), 100e18);
        vault.BASE_ASSET().approve(address(l1BasicMint), 100e18);
        l1BasicMint.depositAndXCall(IVault(address(vault)), lockbox, xErc20, amountOfBase, destination, to, slippage);
    }
}
