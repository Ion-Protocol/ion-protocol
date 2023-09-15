// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {IIonPool} from "./interfaces/IIonPool.sol";
import {Vat} from "./Vat.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract IonPool is IIonPool {
    using SafeERC20 for IERC20;

    Vat public vat;
    IERC20 baseAsset;
    mapping(bytes32 ilkId => IERC20 ilk) public ilks;

    constructor(Vat _vat) {
        vat = _vat;
    }

    function supply(uint256 amount) external {}

    function redeem(uint256 amount) external {}

    function exit(uint256 amount) external {}

    function join(uint256 amount) external {}
}
