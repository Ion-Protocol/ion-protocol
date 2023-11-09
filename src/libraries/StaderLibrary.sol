// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IStaderStakePoolsManager, IStaderOracle } from "src/interfaces/ProviderInterfaces.sol";
import { WadRayMath } from "src/libraries/math/WadRayMath.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

library StaderLibrary {
    using WadRayMath for uint256;
    using Math for uint256;

    function getEthAmountInForLstAmountOut(
        IStaderStakePoolsManager staderDeposit,
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
        IStaderStakePoolsManager staderDeposit,
        uint256 ethAmount
    )
        internal
        view
        returns (uint256)
    {
        return staderDeposit.previewDeposit(ethAmount);
    }

    function depositForLst(IStaderStakePoolsManager staderDeposit, uint256 ethAmount) internal returns (uint256) {
        return staderDeposit.deposit{ value: ethAmount }(address(this));
    }

    function depositForLst(
        IStaderStakePoolsManager staderDeposit,
        uint256 ethAmount,
        address receiver
    )
        internal
        returns (uint256)
    {
        return staderDeposit.deposit{ value: ethAmount }(receiver);
    }
}
