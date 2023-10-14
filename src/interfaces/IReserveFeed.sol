// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.21;

/**
 * @title IReserveFeed interface
 * @notice Interface for the reserve feeds for Ion Protocol.
 *
 */

interface IReserveFeed {
    /**
     * @dev updates the total reserve of the validator backed asset
     * @param token the address of the asset
     * @param reserve the total ETH reserve of the asset in wei
     */
    function updateReserve(address token, uint256 reserve) external;

    /**
     * @dev returns the total reserve of the validator backed asset
     * @param token the address of the asset
     * @return the total ETH reserve of the asset in wei
     */
    function reserves(address token) external view returns (uint256);
}
