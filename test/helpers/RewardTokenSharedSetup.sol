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
    uint256 internal constant INITIAL_UNDERYLING = 1000e18;
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

    function setUp() external {
        underlying = new ERC20PresetMinterPauser("WETH", "Wrapped Ether");
        underlying.mint(address(this), INITIAL_UNDERYLING);
        rewardToken = new RewardTokenExternal(address(underlying), TREASURY, DECIMALS, NAME, SYMBOL);
    }

    function test_setUp() external {
        assertEq(rewardToken.name(), NAME);
        assertEq(rewardToken.symbol(), SYMBOL);

        assertEq(underlying.balanceOf(address(this)), INITIAL_UNDERYLING);
        assertEq(underlying.balanceOf(address(rewardToken)), 0);
    }
}
