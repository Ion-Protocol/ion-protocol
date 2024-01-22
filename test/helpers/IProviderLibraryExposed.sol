// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IProviderLibraryExposed {
    function getEthAmountInForLstAmountOut(uint256 lstAmount) external view returns (uint256);

    function getLstAmountOutForEthAmountIn(uint256 ethAmount) external view returns (uint256);
}
