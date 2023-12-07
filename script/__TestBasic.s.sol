// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { WETH_ADDRESS, WSTETH_ADDRESS, STADER_STAKE_POOLS_MANAGER_ADDRESS, SWETH_ADDRESS } from "src/constants.sol";
import { IonPool } from "../src/IonPool.sol";
import { IonZapper } from "../src/periphery/IonZapper.sol";
import { IWETH9 } from "../src/interfaces/IWETH9.sol";

import { WstEthHandler } from "../src/flash/handlers/WstEthHandler.sol";
import { EthXHandler } from "../src/flash/handlers/EthXHandler.sol";
import { SwEthHandler } from "../src/flash/handlers/SwEthHandler.sol";
import { IonHandlerBase } from "../src/flash/handlers/base/IonHandlerBase.sol";

import { LidoLibrary } from "../src/libraries/LidoLibrary.sol";
import { StaderLibrary } from "../src/libraries/StaderLibrary.sol";
import { SwellLibrary } from "../src/libraries/SwellLibrary.sol";

import { IWstEth, IStaderStakePoolsManager, ISwEth } from "../src/interfaces/ProviderInterfaces.sol";

import { BaseScript } from "./Base.s.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { VmSafe } from "forge-std/Vm.sol";

IWETH9 constant WETH = IWETH9(WETH_ADDRESS);
IWstEth constant WSTETH = IWstEth(WSTETH_ADDRESS);
IStaderStakePoolsManager constant STADER_MANAGER = IStaderStakePoolsManager(STADER_STAKE_POOLS_MANAGER_ADDRESS);
ISwEth constant SWETH = ISwEth(SWETH_ADDRESS);

using LidoLibrary for IWstEth;
using StaderLibrary for IStaderStakePoolsManager;
using SwellLibrary for ISwEth;

contract Addresses is BaseScript {
    string configPath = "./deployment-config/DeployedAddresses.json";
    string config = vm.readFile(configPath);

    IonPool pool = IonPool(vm.parseJsonAddress(config, ".ionPool"));
    IonZapper ionZapper = IonZapper(vm.parseJsonAddress(config, ".ionZapper"));
    WstEthHandler wstEthHandler = WstEthHandler(payable(vm.parseJsonAddress(config, ".wstEthHandler")));
    EthXHandler ethXHandler = EthXHandler(payable(vm.parseJsonAddress(config, ".ethXHandler")));
    SwEthHandler swEthHandler = SwEthHandler(payable(vm.parseJsonAddress(config, ".swEthHandler")));

    VmSafe.Wallet lender1 = vm.createWallet("lender1");
    VmSafe.Wallet lender2 = vm.createWallet("lender2");
    VmSafe.Wallet lender3 = vm.createWallet("lender3");

    VmSafe.Wallet borrower1 = vm.createWallet("borrower1");
    VmSafe.Wallet borrower2 = vm.createWallet("borrower2");
    VmSafe.Wallet borrower3 = vm.createWallet("borrower3");
}

contract SetUp is Addresses {
    function info(address user) public view {
        console2.log("--- ", user, " ---");

        (uint256 collateral0, uint256 normalizedDebt0) = pool.vault(0, user);
        (uint256 collateral1, uint256 normalizedDebt1) = pool.vault(1, user);
        (uint256 collateral2, uint256 normalizedDebt2) = pool.vault(2, user);

        console2.log("rewardToken Balance: ", pool.balanceOf(user));
        console2.log("collateral0: ", collateral0);
        console2.log("normalizedDebt0: ", normalizedDebt0);
        console2.log("collateral1: ", collateral1);
        console2.log("normalizedDebt1: ", normalizedDebt1);
        console2.log("collateral2: ", collateral2);
        console2.log("normalizedDebt2: ", normalizedDebt2);
    }

    // TODO: When called alone from run(), requires --private-key flag to unlock the wallet.
    // But when called together with other broadcasts, does not require a --private-key flag.
    function adminInit() internal broadcast {
        pool.updateSupplyCap(type(uint256).max);
        pool.updateIlkDebtCeiling(0, type(uint256).max);
        pool.updateIlkDebtCeiling(1, type(uint256).max);
        pool.updateIlkDebtCeiling(2, type(uint256).max);
    }

    function fund(address user, uint256 amount) internal broadcast {
        user.call{ value: amount }("");
    }

    function supply(address user, uint256 sk, uint256 amount) internal broadcastFromSk(sk) {
        WETH.deposit{ value: amount }();
        WETH.approve(address(pool), amount);
        pool.supply(user, amount, new bytes32[](0));
    }

    function zapSupply(uint256 sk, uint256 amount) internal broadcastFromSk(sk) {
        ionZapper.zapSupply{ value: amount }(new bytes32[](0));
    }

    function borrow(
        address user,
        uint256 sk,
        uint8 ilkIndex,
        uint256 depositAmount,
        uint256 borrowAmount
    )
        internal
        broadcastFromSk(sk)
    {
        address collateral = pool.getIlkAddress(ilkIndex);

        IonHandlerBase handler;
        uint256 mintedAmount;
        if (ilkIndex == 0) {
            handler = wstEthHandler;
            mintedAmount = WSTETH.depositForLst(depositAmount);
        } else if (ilkIndex == 1) {
            handler = ethXHandler;
            mintedAmount = STADER_MANAGER.depositForLst({ ethAmount: depositAmount, receiver: user });
        } else if (ilkIndex == 2) {
            handler = swEthHandler;
            mintedAmount = SWETH.depositForLst(depositAmount);
        }

        IERC20(collateral).approve(address(handler), mintedAmount);
        pool.addOperator(address(handler));
        IonHandlerBase(handler).depositAndBorrow(mintedAmount, borrowAmount, new bytes32[](0));
    }

    // forge script script/__TestBasic.s.sol --tc SetUp --rpc-url http://localhost:8545 --private-key $PRIVATE_KEY
    // --broadcast --slow -vvvv
    // If encountering Query Nonce Error, just retry
    function run() public virtual {
        adminInit();

        // fund ether from deployer wallet
        // NOTE: If anvil wallet runs out of ether, this will call application panic
        // TODO: How to fund anvil wallet with more ether and broadcast?
        fund(lender1.addr, 200 ether);
        fund(lender2.addr, 200 ether);
        fund(lender3.addr, 200 ether);
        fund(borrower1.addr, 100 ether);
        fund(borrower2.addr, 100 ether);
        fund(borrower3.addr, 100 ether);

        // send basic contract interactions
        supply(lender1.addr, lender1.privateKey, 50 ether);
        supply(lender2.addr, lender2.privateKey, 50 ether);
        supply(lender3.addr, lender3.privateKey, 50 ether);

        // test zapSupply
        zapSupply(lender1.privateKey, 50 ether);
        zapSupply(lender2.privateKey, 50 ether);
        zapSupply(lender3.privateKey, 50 ether);

        // test borrow
        borrow(borrower1.addr, borrower1.privateKey, 0, 11 ether, 1.4 ether);
        borrow(borrower1.addr, borrower1.privateKey, 1, 12 ether, 1.5 ether);
        borrow(borrower1.addr, borrower1.privateKey, 2, 13 ether, 1.6 ether);

        borrow(borrower2.addr, borrower2.privateKey, 0, 21 ether, 2.4 ether);
        borrow(borrower2.addr, borrower2.privateKey, 1, 22 ether, 2.5 ether);
        borrow(borrower2.addr, borrower2.privateKey, 2, 23 ether, 2.6 ether);

        borrow(borrower3.addr, borrower3.privateKey, 0, 31 ether, 3.4 ether);
        borrow(borrower3.addr, borrower3.privateKey, 1, 32 ether, 3.5 ether);
        borrow(borrower3.addr, borrower3.privateKey, 2, 33 ether, 3.6 ether);

        info(lender1.addr);
        info(lender2.addr);
        info(lender3.addr);
        info(borrower1.addr);
        info(borrower2.addr);
        info(borrower3.addr);
    }
}

contract AdminInit is SetUp {
    function run() public override {
        adminInit();
    }
}

contract Borrowers is SetUp {
    function run() public override {
        fund(borrower1.addr, 100 ether);
        borrow(borrower1.addr, borrower1.privateKey, 0, 5 ether, 1 ether);
        info(borrower1.addr);
    }
}

contract View is SetUp {
    function run() public view override {
        console2.log("--- Protocol ---");
        console2.log("WETH.balanceOf(address(pool)): ", WETH.balanceOf(address(pool)));
        console2.log("weth: ", pool.weth());

        info(lender1.addr);
        info(lender2.addr);
        info(lender3.addr);
        info(borrower1.addr);
        info(borrower2.addr);
        info(borrower3.addr);
    }
}
