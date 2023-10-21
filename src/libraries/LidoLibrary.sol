// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ILidoStEthDeposit } from "../../src/interfaces/DepositInterfaces.sol";
import { ILidoWStEthDeposit } from "../../src/interfaces/DepositInterfaces.sol";
import { RoundedMath } from "../../src/libraries/math/RoundedMath.sol";

library LidoLibrary {
    using RoundedMath for uint256;

    function getEthAmountInForLstAmount(ILidoWStEthDeposit wstEth, uint256 lstAmount) internal view returns (uint256) {
        ILidoStEthDeposit stEth = ILidoStEthDeposit(wstEth.stETH());
        return lstAmount.wadMulDown(stEth.getTotalPooledEther()).wadDivUp(stEth.getTotalShares());
    }
}
