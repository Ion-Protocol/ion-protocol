// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IRedstonePriceFeed {
    /**
     * @notice Returns details of the latest successful update round
     * @dev It uses few helpful functions to abstract logic of getting
     * latest round id and value
     * @return roundId The number of the latest round
     * @return answer The latest reported value
     * @return startedAt Block timestamp when the latest successful round started
     * @return updatedAt Block timestamp of the latest successful round
     * @return answeredInRound The number of the latest round
     */
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
