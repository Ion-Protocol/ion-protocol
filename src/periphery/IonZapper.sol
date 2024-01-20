// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../IonPool.sol";
import { RAY } from "../libraries/math/WadRayMath.sol";
import { IWETH9 } from "../interfaces/IWETH9.sol";
import { Whitelist } from "../Whitelist.sol";
import { IWstEth } from "../interfaces/ProviderInterfaces.sol";
import { GemJoin } from "../join/GemJoin.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice A peripheral helper contract to interact with the `IonPool` and the
 * WstEth `GemJoin` even when holding StEth and native Ether. At the core level,
 * the `IonPool` only interacts with WstEth and WETH. This contract will allow
 * users to deposit StEth and native Ether into the `IonPool` by auto-wrapping
 * on the user's behalf.
 * 
 * @custom:security-contact security@molecularlabs.io
 */
contract IonZapper {
    IonPool public immutable POOL;
    IWETH9 public immutable WETH;

    IERC20 public immutable STETH;
    IWstEth public immutable WSTETH;
    GemJoin public immutable WSTETH_JOIN;

    Whitelist public immutable WHITELIST;

    /**
     * @notice Checks if `msg.sender` is on the whitelist.
     * @dev This contract will be on the `protocolControlledWhitelist`. As such,
     * it will validate that users are on the whitelist itself and be able to
     * bypass the whitelist check on `IonPool`.
     * @param proof to validate the whitelist check.
     */
    modifier onlyWhitelistedLenders(bytes32[] memory proof) {
        WHITELIST.isWhitelistedLender(msg.sender, msg.sender, proof);
        _;
    }

    /**
     * @notice Creates a new `IonZapper` instance. 
     * @param _ionPool `IonPool` contract address.
     * @param _weth `WETH9` contract address.
     * @param _stEth `StEth` contract address.
     * @param _wstEth `WstEth` contract address.
     * @param _wstEthJoin `GemJoin` contract address associated with WstEth.
     * @param _whitelist `Whitelist` contract address.
     */
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

    /**
     * @notice Deposits WETH into the `IonPool` by auto-wrapping the user's
     * native ether on their behalf.
     * @param proof to validate the whitelist check.
     */
    function zapSupply(bytes32[] calldata proof) external payable onlyWhitelistedLenders(proof) {
        uint256 amount = msg.value;

        WETH.deposit{ value: amount }();
        POOL.supply(msg.sender, amount, proof);
    }

    /**
     * @notice Repays WETH into the `IonPool` by auto-wrapping the user's native
     * ether on their behalf. 
     * @param ilkIndex of the collateral.
     */
    function zapRepay(uint8 ilkIndex) external payable {
        uint256 amount = msg.value;

        uint256 currentIlkRate = POOL.rate(ilkIndex);

        uint256 normalizedAmountToRepay = amount * RAY / currentIlkRate;

        WETH.deposit{ value: amount }();
        POOL.repay(ilkIndex, msg.sender, address(this), normalizedAmountToRepay);
    }

    /**
     * @notice Deposits WstEth into the WstEth `GemJoin` by auto-wrapping the
     * user's StEth on their behalf.
     * @param amountStEth to gem-join. [WAD]
     */
    function zapJoinWstEth(uint256 amountStEth) external {
        STETH.transferFrom(msg.sender, address(this), amountStEth);

        uint256 outputWstEthAmount = WSTETH.wrap(amountStEth);
        WSTETH_JOIN.join(msg.sender, outputWstEthAmount);
    }
}
