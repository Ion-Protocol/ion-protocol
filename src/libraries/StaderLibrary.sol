// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IStaderDeposit, IStaderOracle } from "src/interfaces/DepositInterfaces.sol";
import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library StaderLibrary {
    using RoundedMath for uint256;
    using Math for uint256;

    function getEthAmountInForLstAmountOut(
        IStaderDeposit staderDeposit,
        uint256 lstAmount
    )
        internal
        view
        returns (uint256)
    {
        uint256 supply = IStaderOracle(staderDeposit.staderConfig().getStaderOracle()).getExchangeRate().totalETHXSupply;
        return lstAmount.mulDiv(staderDeposit.totalAssets(), supply, Math.Rounding.Ceil);
    }

    function getLstAmountOutForEthAmountIn(
        IStaderDeposit staderDeposit,
        uint256 ethAmount
    )
        internal
        view
        returns (uint256)
    {
        return staderDeposit.previewDeposit(ethAmount);
    }

    function depositForLst(IStaderDeposit staderDeposit, uint256 ethAmount) internal returns (uint256) {
        return staderDeposit.deposit{ value: ethAmount }(address(this));
    }
}
