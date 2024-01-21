// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IStaderStakePoolsManager, IStaderOracle } from "../interfaces/ProviderInterfaces.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StaderLibrary
 * 
 * @notice A helper library for Stader-related conversions.
 * 
 * @custom:security-contact security@molecularlabs.io
 */
library StaderLibrary {
    using Math for uint256;

    /**
     * @notice Returns the amount of ETH needed to mint the given amount of ETHx.
     * @param staderDeposit address.
     * @param lstAmount Desired output amount. [WAD]
     */
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

    /**
     * @notice Returns the amount of ETHx that can be minted with the given amount of ETH.
     * @param staderDeposit address.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     */
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

    /**
     * @notice Deposits ETH into the stader deposit contract and returns the amount of ETHx received.
     * @param staderDeposit address.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     */
    function depositForLst(IStaderStakePoolsManager staderDeposit, uint256 ethAmount) internal returns (uint256) {
        return staderDeposit.deposit{ value: ethAmount }(address(this));
    }

    /**
     * @notice Deposits ETH into the stader deposit contract and returns the amount of ETHx received.
     * 
     * This function parameterizes the address to receive the ETHx.
     * @param staderDeposit address.
     * @param ethAmount Amount of ETH to deposit. [WAD]
     * @param receiver to receive the ETHx.
     */
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
