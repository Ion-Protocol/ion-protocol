// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IXERC20 {
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

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BridgeLimitsSet(uint256 _mintingLimit, uint256 _burningLimit, address indexed _bridge);
    event EIP712DomainChanged();
    event LockboxSet(address _lockbox);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function FACTORY() external view returns (address);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function bridges(address)
        external
        view
        returns (BridgeParameters memory minterParams, BridgeParameters memory burnerParams);
    function burn(address _user, uint256 _amount) external;
    function burningCurrentLimitOf(address _bridge) external view returns (uint256 _limit);
    function burningMaxLimitOf(address _bridge) external view returns (uint256 _limit);
    function decimals() external view returns (uint8);
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        );
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
    function lockbox() external view returns (address);
    function mint(address _user, uint256 _amount) external;
    function mintingCurrentLimitOf(address _bridge) external view returns (uint256 _limit);
    function mintingMaxLimitOf(address _bridge) external view returns (uint256 _limit);
    function name() external view returns (string memory);
    function nonces(address owner) external view returns (uint256);
    function owner() external view returns (address);
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external;
    function renounceOwnership() external;
    function setLimits(address _bridge, uint256 _mintingLimit, uint256 _burningLimit) external;
    function setLockbox(address _lockbox) external;
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transferOwnership(address newOwner) external;
}
