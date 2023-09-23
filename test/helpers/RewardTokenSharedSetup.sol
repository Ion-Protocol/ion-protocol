// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {RewardToken} from "../../src/token/RewardToken.sol";
import {RoundedMath} from "../../src/math/RoundedMath.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract RewardTokenExternal is RewardToken {
    constructor(address _underlying, address _treasury, uint8 decimals_, string memory name_, string memory symbol_)
        RewardToken(_underlying, _treasury, decimals_, name_, symbol_)
    {}

    // --- Cheats ---
    function setSupplyFactor(uint256 factor) external {
        supplyFactor = factor;
    }

    function getSupplyFactor() external view returns (uint256) {
        return supplyFactor;
    }

    // --- Expose Internal ---
    function burn(address user, address receiverOfUnderlying, uint256 amount) external {
        _burn(user, receiverOfUnderlying, amount);
    }

    function mint(address user, uint256 amount) external {
        _mint(user, amount);
    }

    function mintToTreasury(uint256 amount) external {
        _mintToTreasury(amount);
    }

    // --- Expose Events ---
    function emitMint(address user, uint256 amount, uint256 index) external {
        emit Mint(user, amount, index);
    }

    function emitBurn(address user, address receiverOfUnderlying, uint256 amount, uint256 index) external {
        emit Burn(user, receiverOfUnderlying, amount, index);
    }

    function emitTransfer(address from, address to, uint256 value) external {
        emit Transfer(from, to, value);
    }

    function emitBalanceTransfer(address from, address to, uint256 value, uint256 index) external {
        emit BalanceTransfer(from, to, value, index);
    }
}

abstract contract RewardTokenSharedSetup is Test {
    using RoundedMath for uint256;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BalanceTransfer(address indexed from, address indexed to, uint256 value, uint256 index);
    event Burn(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor);
    event Mint(address indexed user, uint256 amount, uint256 supplyFactor);
    event Transfer(address indexed from, address indexed to, uint256 value);

    RewardTokenExternal rewardToken;
    ERC20PresetMinterPauser underlying;
    address internal TREASURY = vm.addr(2);
    uint8 internal constant DECIMALS = 18;
    string internal constant SYMBOL = "iWETH";
    string internal constant NAME = "Ion Wrapped Ether";

    uint256 sendingUserPrivateKey = 16;
    uint256 receivingUserPrivateKey = 17;
    uint256 spenderPrivateKey = 18;
    address sendingUser = vm.addr(sendingUserPrivateKey); // random address
    address receivingUser = vm.addr(receivingUserPrivateKey); // random address
    address spender = vm.addr(spenderPrivateKey); // random address

    function setUp() public virtual {
        underlying = new ERC20PresetMinterPauser("WETH", "Wrapped Ether");
        rewardToken = new RewardTokenExternal(address(underlying), TREASURY, DECIMALS, NAME, SYMBOL);
    }

    // --- Helpers ---

    function _depositInterestGains(uint256 amount) internal {
        underlying.mint(address(rewardToken), amount);
    }

    function _wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b / 1e18;
    }

    function _calculateMalleableSignature(uint8 v, bytes32 r, bytes32 s)
        internal
        pure
        returns (uint8, bytes32, bytes32)
    {
        // Ensure v is within the valid range (27 or 28)
        require(v == 27 || v == 28, "Invalid v value");

        // Calculate the other s value by negating modulo the curve order n
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        uint256 otherS = n - uint256(s);

        // Calculate the other v value
        uint8 otherV = 55 - v;

        return (otherV, r, bytes32(otherS));
    }
}
