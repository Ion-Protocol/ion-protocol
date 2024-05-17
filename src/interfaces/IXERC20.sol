// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IXERC20 is IERC20 {
    /**
     * @notice Contains the full minting and burning data for a particular bridge
     *
     * @param minterParams The minting parameters for the bridge
     * @param burnerParams The burning parameters for the bridge
     */
    struct Bridge {
        BridgeParameters minterParams;
        BridgeParameters burnerParams;
    }

    struct BridgeParameters {
        uint256 timestamp;
        uint256 ratePerSecond;
        uint256 maxLimit;
        uint256 currentLimit;
    }

    error IXERC20_LimitsTooHigh();
    error IXERC20_NotFactory();
    error IXERC20_NotHighEnoughLimits();
    error InvalidShortString();
    error StringTooLong(string str);

    event BridgeLimitsSet(uint256 _mintingLimit, uint256 _burningLimit, address indexed _bridge);
    event LockboxSet(address _lockbox);

    function FACTORY() external view returns (address);
    function bridges(address)
        external
        view
        returns (BridgeParameters memory minterParams, BridgeParameters memory burnerParams);
    function burn(address _user, uint256 _amount) external;
    function burningCurrentLimitOf(address _bridge) external view returns (uint256 _limit);
    function burningMaxLimitOf(address _bridge) external view returns (uint256 _limit);
    function lockbox() external view returns (address);
    function mint(address _user, uint256 _amount) external;
    function mintingCurrentLimitOf(address _bridge) external view returns (uint256 _limit);
    function mintingMaxLimitOf(address _bridge) external view returns (uint256 _limit);
    function setLimits(address _bridge, uint256 _mintingLimit, uint256 _burningLimit) external;
    function setLockbox(address _lockbox) external;
}
