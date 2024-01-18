// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../../../src/IonPool.sol";
import { IonZapper } from "../../../src/periphery/IonZapper.sol";
import { Whitelist } from "../../../src/Whitelist.sol";
import { IWETH9 } from "../../../src/interfaces/IWETH9.sol";
import { IWstEth, IStEth, ISwEth } from "../../../src/interfaces/ProviderInterfaces.sol";
import { LidoLibrary } from "../../../src/libraries/LidoLibrary.sol";
import { RAY } from "../../../src/libraries/math/WadRayMath.sol";

import { IonPoolSharedSetup } from "../../helpers/IonPoolSharedSetup.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { safeconsole as console } from "forge-std/safeconsole.sol";

contract IonZapper_ForkTest is IonPoolSharedSetup {
    using LidoLibrary for IWstEth;

    IonZapper public ionZapper;

    IWETH9 constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IWstEth constant WSTETH = IWstEth(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IStEth constant STETH = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    address constant ETHX = 0xA35b1B31Ce002FBF2058D22F30f95D405200A15b;
    ISwEth constant SWELL = ISwEth(0xf951E335afb289353dc249e82926178EaC7DEd78);

    function setUp() public override {
        super.setUp();

        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        ionZapper = new IonZapper(
            ionPool,
            WETH,
            IERC20(address(STETH)),
            WSTETH,
            gemJoins[0], // WSTETH_JOIN
            Whitelist(whitelist)
        );
    }

    function test_ZapSupply() public {
        uint256 amount = 1 ether;

        ionZapper.zapSupply{ value: amount }(new bytes32[](0));

        assertEq(address(ionZapper).balance, 0);
        assertEq(WETH.balanceOf(address(ionZapper)), 0);
        assertEq(ionPool.balanceOf(address(this)), amount);
        assertEq(WETH.balanceOf(address(ionPool)), amount);
    }

    function test_ZapRepay() public {
        uint256 supplyAmount = 5 ether;
        ionZapper.zapSupply{ value: supplyAmount }(new bytes32[](0));

        uint256 borrowCollateralAmount = 10 ether;
        uint256 borrowAmount = 3 ether;

        uint256 wethForBorrowCollateralAmount = WSTETH.getEthAmountInForLstAmountOut(borrowCollateralAmount);

        WSTETH.depositForLst(wethForBorrowCollateralAmount);
        IERC20(address(WSTETH)).approve(address(gemJoins[0]), type(uint256).max);
        gemJoins[0].join(address(this), borrowCollateralAmount);
        ionPool.depositCollateral({
            ilkIndex: 0,
            user: address(this),
            depositor: address(this),
            amount: borrowCollateralAmount,
            proof: new bytes32[](0)
        });

        ionPool.borrow({
            ilkIndex: 0,
            user: address(this),
            recipient: address(this),
            amountOfNormalizedDebt: borrowAmount,
            proof: new bytes32[](0)
        });

        uint256 addressThisBalance = address(this).balance;

        assertEq(ionPool.rate(0) * ionPool.normalizedDebt(0, address(this)), borrowAmount * RAY);
        assertEq(WETH.balanceOf(address(this)), borrowAmount);

        WETH.withdraw(borrowAmount);

        assertEq(WETH.balanceOf(address(this)), 0);
        assertEq(address(this).balance - addressThisBalance, borrowAmount);

        ionZapper.zapRepay{ value: borrowAmount }(0);

        assertEq(ionPool.rate(0) * ionPool.normalizedDebt(0, address(this)), 0);
        assertEq(addressThisBalance, address(this).balance);
    }

    function test_ZapDepositWstEth() public {
        uint256 amountEthIn = 1 ether;
        uint256 amountStEth = STETH.submit{ value: amountEthIn }(address(this));

        IERC20 stEthErc20 = IERC20(address(STETH));

        stEthErc20.approve(address(ionZapper), type(uint256).max);

        ionZapper.zapJoinWstEth(amountStEth);

        assertEq(WSTETH.getWstETHByStETH(amountStEth), IERC20(address(WSTETH)).balanceOf(address(gemJoins[0])));
        assertEq(WSTETH.getWstETHByStETH(amountStEth), ionPool.gem(0, address(this)));
    }

    function _getCollaterals() internal pure override returns (IERC20[] memory _collaterals) {
        _collaterals = new IERC20[](3);

        _collaterals[0] = IERC20(address(WSTETH));
        _collaterals[1] = IERC20(ETHX);
        _collaterals[2] = IERC20(address(SWELL));
    }

    function _getUnderlying() internal pure override returns (address _underlying) {
        _underlying = address(WETH);
    }

    receive() external payable {}
}
