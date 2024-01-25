// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

/**
 * @title IReserveFeed interface
 * @notice Interface for the reserve feeds for Ion Protocol.
 *
 */
interface IReserveFeed {
    /**
     * @dev updates the total reserve of the validator backed asset
     * @param ilkIndex the ilk index of the asset
     * @param reserve the total ETH reserve of the asset in wei
     */
    function updateExchangeRate(uint8 ilkIndex, uint256 reserve) external;

    /**
     * @dev returns the total reserve of the validator backed asset
     * @param ilkIndex the ilk index of the asset
     * @return the total ETH reserve of the asset in wei
     */
    function getExchangeRate(uint8 ilkIndex) external view returns (uint256);
}
