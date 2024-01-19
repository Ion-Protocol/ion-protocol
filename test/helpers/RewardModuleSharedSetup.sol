// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { RewardModule } from "../../src/reward/RewardModule.sol";
import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";
import { TransparentUpgradeableProxy } from "../../src/admin/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "../../src/admin/ProxyAdmin.sol";

import { BaseTestSetup } from "./BaseTestSetup.sol";

contract RewardModuleExposed is RewardModule {
    function init(
        address _underlying,
        address _treasury,
        uint8 decimals_,
        string memory name_,
        string memory symbol_
    )
        external
        initializer
    {
        RewardModule._initialize(_underlying, _treasury, decimals_, name_, symbol_);
    }

    // --- Cheats ---
    function setSupplyFactor(uint256 factor) external {
        _setSupplyFactor(factor);
    }

    // --- Expose Internal ---
    function burn(address user, address receiverOfUnderlying, uint256 amount) external {
        _burn(user, receiverOfUnderlying, amount);
    }

    function mint(address user, uint256 amount) external {
        _mint(user, user, amount);
    }

    function mintToTreasury(uint256 amount) external {
        _mintToTreasury(amount);
    }

    function calculateRewardAndDebtDistribution()
        public
        view
        override
        returns (
            uint256 totalSupplyFactorIncrease,
            uint256 totalTreasuryMintAmount,
            uint104[] memory rateIncreases,
            uint256 totalDebtIncrease,
            uint48[] memory timestampIncreases
        ) {}

}

abstract contract RewardModuleSharedSetup is BaseTestSetup {
    using WadRayMath for uint256;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event BalanceTransfer(address indexed from, address indexed to, uint256 value, uint256 index);
    event Burn(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor);
    event Mint(address indexed user, uint256 amount, uint256 supplyFactor);
    event Transfer(address indexed from, address indexed to, uint256 value);

    RewardModuleExposed rewardModule;
    ProxyAdmin ionProxyAdmin;

    uint256 sendingUserPrivateKey = 16;
    uint256 receivingUserPrivateKey = 17;
    uint256 spenderPrivateKey = 18;
    address sendingUser = vm.addr(sendingUserPrivateKey); // random address
    address receivingUser = vm.addr(receivingUserPrivateKey); // random address
    address spender = vm.addr(spenderPrivateKey); // random address

    function setUp() public virtual override {
        super.setUp();
        ionProxyAdmin = new ProxyAdmin(address(this));
        RewardModuleExposed rewardModuleImpl = new RewardModuleExposed();

        bytes memory initializeBytes = abi.encodeWithSelector(
            RewardModuleExposed.init.selector, address(underlying), address(TREASURY), DECIMALS, NAME, SYMBOL
        );

        rewardModule = RewardModuleExposed(
            address(
                new TransparentUpgradeableProxy(
                    address(rewardModuleImpl),
                    address(ionProxyAdmin),
                    initializeBytes
                )
            )
        );
    }

    function test_Initialize() external {
        ProxyAdmin _admin = new ProxyAdmin(address(this));
        RewardModuleExposed _rewardModuleImpl = new RewardModuleExposed();

        bytes memory initializeBytes = abi.encodeWithSelector(
            RewardModuleExposed.init.selector, address(0), address(TREASURY), DECIMALS, NAME, SYMBOL
        );

        vm.expectRevert(RewardModule.InvalidUnderlyingAddress.selector);
        rewardModule = RewardModuleExposed(
            address(
                new TransparentUpgradeableProxy(
                    address(_rewardModuleImpl),
                    address(_admin),
                    initializeBytes
                )
            )
        );

        initializeBytes = abi.encodeWithSelector(
            RewardModuleExposed.init.selector, address(underlying), address(0), DECIMALS, NAME, SYMBOL
        );

        vm.expectRevert(RewardModule.InvalidTreasuryAddress.selector);
        rewardModule = RewardModuleExposed(
            address(
                new TransparentUpgradeableProxy(
                    address(_rewardModuleImpl),
                    address(_admin),
                    initializeBytes
                )
            )
        );

        initializeBytes = abi.encodeWithSelector(
            RewardModuleExposed.init.selector, address(underlying), address(TREASURY), DECIMALS, NAME, SYMBOL
        );
        rewardModule = RewardModuleExposed(
            address(
                new TransparentUpgradeableProxy(
                    address(_rewardModuleImpl),
                    address(_admin),
                    initializeBytes
                )
            )
        );
    }

    // --- Helpers ---

    function _depositInterestGains(uint256 amount) public {
        underlying.mint(address(rewardModule), amount);
    }

    function _calculateMalleableSignature(
        uint8 v,
        bytes32 r,
        bytes32 s
    )
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
