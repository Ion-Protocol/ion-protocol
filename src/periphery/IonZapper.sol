// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../IonPool.sol";
import { RAY } from "../libraries/math/WadRayMath.sol";
import { IWETH9 } from "../interfaces/IWETH9.sol";
import { Whitelist } from "../Whitelist.sol";
import { IWstEth } from "../interfaces/ProviderInterfaces.sol";
import { GemJoin } from "../join/GemJoin.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IonZapper {
    IonPool public immutable POOL;
    IWETH9 public immutable WETH;

    IERC20 public immutable STETH;
    IWstEth public immutable WSTETH;
    GemJoin public immutable WSTETH_JOIN;

    Whitelist public immutable WHITELIST;

    modifier onlyWhitelistedLenders(bytes32[] memory proof) {
        WHITELIST.isWhitelistedLender(msg.sender, msg.sender, proof);
        _;
    }

    constructor(
        IonPool _ionPool,
        IWETH9 _weth,
        IERC20 _stEth,
        IWstEth _wstEth,
        GemJoin _wstEthJoin,
        Whitelist _whitelist
    ) {
        POOL = _ionPool;
        WETH = _weth;

        STETH = _stEth;
        WSTETH = _wstEth;
        WSTETH_JOIN = _wstEthJoin;

        WHITELIST = _whitelist;
        _weth.approve(address(_ionPool), type(uint256).max);
        _stEth.approve(address(_wstEth), type(uint256).max);
        IERC20(address(_wstEth)).approve(address(_wstEthJoin), type(uint256).max);
    }

    function zapSupply(bytes32[] calldata proof) external payable onlyWhitelistedLenders(proof) {
        uint256 amount = msg.value;

        WETH.deposit{ value: amount }();
        POOL.supply(msg.sender, amount, proof);
    }

    function zapRepay(uint8 ilkIndex) external payable {
        uint256 amount = msg.value;

        uint256 currentIlkRate = POOL.rate(ilkIndex);
        (,, uint256 ilkRateIncrease,,) = POOL.calculateRewardAndDebtDistribution(ilkIndex);
        uint256 newIlkRate = currentIlkRate + ilkRateIncrease;

        uint256 normalizedAmountToRepay = amount * RAY / newIlkRate;

        WETH.deposit{ value: amount }();
        POOL.repay(ilkIndex, msg.sender, address(this), normalizedAmountToRepay);
    }

    function zapJoinWstEth(uint256 amountStEth) external {

        STETH.transferFrom(msg.sender, address(this), amountStEth);

        uint256 outputWstEthAmount = WSTETH.wrap(amountStEth);
        WSTETH_JOIN.join(msg.sender, outputWstEthAmount);
    }
}
