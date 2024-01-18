// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {
    WETH_ADDRESS,
    WSTETH_ADDRESS,
    ETHX_ADDRESS,
    STADER_STAKE_POOLS_MANAGER_ADDRESS,
    SWETH_ADDRESS
} from "src/constants.sol";
import { IonPool } from "src/IonPool.sol";
import { IonZapper } from "src/periphery/IonZapper.sol";
import { IWETH9 } from "src/interfaces/IWETH9.sol";

import { WstEthHandler } from "src/flash/handlers/WstEthHandler.sol";
import { EthXHandler } from "src/flash/handlers/EthXHandler.sol";
import { SwEthHandler } from "src/flash/handlers/SwEthHandler.sol";
import { IonHandlerBase } from "src/flash/handlers/base/IonHandlerBase.sol";

import { LidoLibrary } from "src/libraries/LidoLibrary.sol";
import { StaderLibrary } from "src/libraries/StaderLibrary.sol";
import { SwellLibrary } from "src/libraries/SwellLibrary.sol";

import { IWstEth, IStaderStakePoolsManager, ISwEth } from "src/interfaces/ProviderInterfaces.sol";

import { BaseScript } from "script/Base.s.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

IWETH9 constant WETH = IWETH9(WETH_ADDRESS);
IWstEth constant WSTETH = IWstEth(WSTETH_ADDRESS);
IStaderStakePoolsManager constant STADER_MANAGER = IStaderStakePoolsManager(STADER_STAKE_POOLS_MANAGER_ADDRESS);
ISwEth constant SWETH = ISwEth(SWETH_ADDRESS);

using LidoLibrary for IWstEth;
using StaderLibrary for IStaderStakePoolsManager;
using SwellLibrary for ISwEth;

IUniswapV3Pool constant SWETH_ETH_POOL = IUniswapV3Pool(0x30eA22C879628514f1494d4BBFEF79D21A6B49A2);

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

        console2.log("ether balance: ", user.balance);
        console2.log("weth balance: ", IERC20(WETH_ADDRESS).balanceOf(user));
        console2.log("wstETH balance: ", IERC20(WSTETH_ADDRESS).balanceOf(user));
        console2.log("ETHx balance: ", IERC20(ETHX_ADDRESS).balanceOf(user));
        console2.log("swETH balance: ", IERC20(SWETH_ADDRESS).balanceOf(user));

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

    function mintWeth(uint256 sk, uint256 amount) internal broadcastFromSk(sk) {
        WETH.deposit{ value: amount }();
    }

    function fundCollateral(uint8 ilkIndex, address user, uint256 amount) internal broadcast {
        IERC20 collateral = IERC20(pool.getIlkAddress(ilkIndex));
        IonHandlerBase handler;
        WETH.deposit{ value: amount }();
        uint256 mintedAmount;
        if (ilkIndex == 0) {
            handler = wstEthHandler;
            mintedAmount = WSTETH.depositForLst(amount);
        } else if (ilkIndex == 1) {
            handler = ethXHandler;
            mintedAmount = STADER_MANAGER.depositForLst({ ethAmount: amount, receiver: user });
        } else if (ilkIndex == 2) {
            handler = swEthHandler;
            mintedAmount = SWETH.depositForLst(amount);
        }
        if (user != broadcaster) {
            collateral.transfer(user, mintedAmount);
        }
    }

    function supply(address user, uint256 sk, uint256 amount) internal broadcastFromSk(sk) {
        WETH.deposit{ value: amount }();
        WETH.approve(address(pool), amount);
        pool.supply(user, amount, new bytes32[](0));
    }

    function supplyWeth(address user, uint256 sk, uint256 amount) internal broadcastFromSk(sk) {
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

contract ZapSupply is SetUp {
    function run() public override {
        zapSupply(0xfa463d3ae3a9deb586e11e8edb99861441f30c58dfc22de4cb3b1e1c07de1182, 100_000 ether);
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

contract CreateBorrowPosition is SetUp {
    function run() public override {
        address pk = 0x190d54A17Bf464b69BDBB0DDa00bfeF979925EAE;
        uint256 sk = 0x3c8c0b954e1873e8bcb1c451349a03348af6cc78355472413aa246588fd13a10;
        fund(pk, 100 ether);
        borrow(pk, sk, 0, 12.123 ether, 6.123 ether);
    }
}

contract FundCollateral is SetUp {
    function run() public override {
        // fund(0x190d54A17Bf464b69BDBB0DDa00bfeF979925EAE, 100 ether);
        address pk = 0x190d54A17Bf464b69BDBB0DDa00bfeF979925EAE;
        fundCollateral(0, pk, 100 ether);
        // fundCollateral(1, pk, 100 ether);
        fundCollateral(2, pk, 100 ether);
    }
}

contract MintWeth is SetUp {
    function run() public override {
        uint256 sk = 0x0;
        mintWeth(sk, 10 ether);
    }
}

contract InterestRate is SetUp {
    function run() public override {
        (uint256 totalDebt, uint256 borrowRate, uint256 reserveFactor) = pool.getCurrentBorrowRate(0);
        console2.log("borrowRate: ", borrowRate);
        console2.log("reserveFactor: ", reserveFactor);
    }
}

contract IncreaseObservationCardinality is SetUp {
    function run() public override broadcast {
        SWETH_ETH_POOL.increaseObservationCardinalityNext(100);
    }
}

contract View is SetUp {
    function run() public view override {
        console2.log("--- Deployer ---");
        console2.log("eth balance: ", broadcaster.balance);

        console2.log("--- Protocol ---");
        console2.log("WETH.balanceOf(address(pool)): ", WETH.balanceOf(address(pool)));
        console2.log("weth: ", pool.weth());
        console2.log("wethSupplyCap: ", pool.wethSupplyCap());
        console2.log(
            "totalDebt: ",
            pool.totalNormalizedDebt(0) * pool.rate(0) + pool.totalNormalizedDebt(1) * pool.rate(1)
                + pool.totalNormalizedDebt(2) * pool.rate(2)
        );

        console2.log("--- wstETH ---");
        console2.log("pool.totalNormalizedDebt: ", pool.totalNormalizedDebt(0));
        console2.log("pool.rate: ", pool.rate(0));
        console2.log("pool debt [rad]: ", pool.totalNormalizedDebt(0) * pool.rate(0));
        console2.log("pool ceiling [rad]: ", pool.debtCeiling(0));
        console2.log("pool ceiling [wad]: ", pool.debtCeiling(0) / 1e27);

        console2.log("--- ETHx ---");
        console2.log("pool.totalNormalizedDebt: ", pool.totalNormalizedDebt(1));
        console2.log("pool.rate: ", pool.rate(1));
        console2.log("pool debt: ", pool.totalNormalizedDebt(1) * pool.rate(1));
        console2.log("pool ceiling [rad]: ", pool.debtCeiling(1));
        console2.log("pool ceiling [wad]: ", pool.debtCeiling(1) / 1e27);

        console2.log("--- ETHx ---");
        console2.log("pool.totalNormalizedDebt: ", pool.totalNormalizedDebt(1));
        console2.log("pool.rate: ", pool.rate(1));
        console2.log("pool debt: ", pool.totalNormalizedDebt(1) * pool.rate(1));
        console2.log("pool ceiling [rad]: ", pool.debtCeiling(1));
        console2.log("pool ceiling [wad]: ", pool.debtCeiling(1) / 1e27);

        info(lender1.addr);
        info(lender2.addr);
        info(lender3.addr);
        info(borrower1.addr);
        info(borrower2.addr);
        info(borrower3.addr);
        info(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        info(0x6450311D9A60c744b8Db774A6B9898938A0fD3eA);
        info(0x7ae4a90F111c670d1C9897AF9DA8FDa9092D3C10); // chunda
        info(0x6436BEA3540Af4DC9095Ff3aB3BB33C9a7A04b38); // alex
    }
}

contract Rate {
    /**
     * @dev x and the returned value are to be interpreted as fixed-point
     * integers with scaling factor b. For example, if b == 100, this specifies
     * two decimal digits of precision and the normal decimal value 2.1 would be
     * represented as 210; rpow(210, 2, 100) returns 441 (the two-decimal digit
     * fixed-point representation of 2.1^2 = 4.41) (From MCD docs)
     * @param x base
     * @param n exponent
     * @param b scaling factor
     */
    function _rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := b }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := b }
                default { z := x }
                let half := div(b, 2) // for rounding.
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, b)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, b)
                    }
                }
            }
        }
    }

    function run() public {
        uint256 borrowRateWithRay = 1_000_000_000_073_542_918_165_030_747;
        uint256 borrowRateExpT = _rpow(borrowRateWithRay, 31_540_000, 1e27);
        console2.log("yearly borrow rate: ", borrowRateExpT);
    }
}
