// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { IonPool } from "./IonPool.sol";
import { WAD } from "./libraries/math/WadRayMath.sol";

import { Math } from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import { ERC4626 } from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Ownable2Step } from "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import { console2 } from "forge-std/console2.sol";

/**
 * @notice Vault contract that can allocate a single lender asset over various
 * isolated pairs on Ion Protocol. This contract is a fork of the Metamorpho
 * contract licnesed under GPL-2.0 with minimal changes to apply the
 * reallocation logic to the Ion isolated pairs.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract Vault is ERC4626, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;

    error InvalidSupplyQueueLength();
    error InvalidWithdrawQueueLength();
    error AllocationCapExceeded();
    error InvalidReallocation();
    error AllSupplyCapsReached();
    error NotEnoughLiquidityToWithdraw();
    error InvalidSupplyQueuePool();
    error InvalidWithdrawQueuePool();

    event UpdateSupplyQueue(address indexed caller, IonPool[] newSupplyQueue);
    event UpdateWithdrawQueue(address indexed caller, IonPool[] newWithdrawQueue);

    event ReallocateWithdraw(IonPool indexed pool, uint256 assets);
    event ReallocateSupply(IonPool indexed pool, uint256 assets);
    event FeeAccrued(uint256 feeShares, uint256 newTotalAssets);
    event UpdateLastTotalAssets(uint256 lastTotalAssets, uint256 newLastTotalAssets);

    EnumerableSet.AddressSet supportedMarkets;
    IonPool[] public supplyQueue;
    IonPool[] public withdrawQueue;

    address feeRecipient;
    uint256 public feePercentage;

    mapping(IonPool => uint256) public caps;
    uint256 public lastTotalAssets;

    IIonLens public immutable ionLens;
    IERC20 public immutable baseAsset;

    struct MarketAllocation {
        IonPool pool;
        uint256 targetAssets;
    }

    constructor(
        address _owner,
        address _feeRecipient,
        IERC20 _baseAsset,
        IIonLens ionLens,
        string memory _name,
        string memory _symbol
    )
        ERC4626(IERC20(_baseAsset))
        ERC20(_name, _symbol)
        Ownable(_owner)
    {
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Add markets that can be supplied and withdrawn from.
     */
    function addSupportedMarkets(IonPool[] calldata markets) external onlyOwner {
        // TODO: The market supported's base asset must be the BASE_ASSET
        for (uint256 i; i < markets.length; ++i) {
            supportedMarkets.add(address(markets[i]));
        }
    }

    /**
     * @notice Update the order of the markets in which user deposits are supplied.
     * @dev The IonPool in the queue must be part of `supportedMarkets`.
     */
    function updateSupplyQueue(IonPool[] calldata newSupplyQueue) external onlyOwner {
        uint256 length = newSupplyQueue.length;
        console2.log("length: ", length);
        if (length != supportedMarkets.length()) revert InvalidSupplyQueueLength();
        for (uint256 i; i < length; ++i) {
            address pool = address(newSupplyQueue[i]);
            if (!supportedMarkets.contains(pool) || pool == address(0)) revert InvalidSupplyQueuePool();
        }

        supplyQueue = newSupplyQueue;

        emit UpdateSupplyQueue(msg.sender, newSupplyQueue);
    }

    /**
     * @notice Update the order of the markets in which the deposits are withdrawn.
     * @dev The IonPool in the queue must be part of `supportedMarkets`.
     */
    function updateWithdrawQueue(IonPool[] calldata newWithdrawQueue) external onlyOwner {
        uint256 length = newWithdrawQueue.length;
        if (length != supportedMarkets.length()) revert InvalidWithdrawQueueLength();
        for (uint256 i; i < length; ++i) {
            if (!supportedMarkets.contains(address(newWithdrawQueue[i]))) revert InvalidWithdrawQueuePool();
        }

        withdrawQueue = newWithdrawQueue;

        emit UpdateWithdrawQueue(msg.sender, newWithdrawQueue);
    }

    /**
     * @notice Receives deposits from the sender and supplies into the underlying IonPool markets.
     * @dev All incoming deposits are deposited in the order specified in the deposit queue.
     */
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        uint256 newTotalAssets = _accrueFee();

        shares = _convertToSharesWithTotals(assets, totalSupply(), newTotalAssets, Math.Rounding.Floor);
        _deposit(msg.sender, receiver, assets, shares);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);

        _supplyToIonPool(assets);

        _updateLastTotalAssets(lastTotalAssets + assets);
    }

    /**
     * @notice Withdraws supplied assets from IonPools and sends them to the receiver in exchange for vault shares.
     * @dev All withdraws are withdrawn in the order specified in the withdraw queue.
     */
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        uint256 newTotalAssets = _accrueFee();

        shares = _convertToSharesWithTotals(assets, totalSupply(), newTotalAssets, Math.Rounding.Ceil);

        _updateLastTotalAssets(newTotalAssets - assets);

        _withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
        override
    {
        _withdrawFromIonPool(assets);

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @notice Reallocates the base asset supply position across the specified IonPools.
     * @dev Depending on the order of deposits and withdrawals to and from
     * markets, the function could revert if there is not enough assets
     * withdrawn to deposit later in the loop. A key invariant is that the total
     * assets withdrawn should be equal to the total assets supplied. Otherwise,
     * revert.
     */
    function reallocate(MarketAllocation[] calldata allocations) external onlyOwner {
        uint256 totalSupplied;
        uint256 totalWithdrawn;
        for (uint256 i; i < allocations.length; ++i) {
            MarketAllocation memory allocation = allocations[i];
            IonPool pool = allocation.pool;

            uint256 targetAssets = allocation.targetAssets;
            uint256 currentSupplied = pool.balanceOf(address(this));

            uint256 toWithdraw = _zeroFloorSub(currentSupplied, targetAssets);

            if (toWithdraw > 0) {
                // if `targetAsset` is zero, this means fully withdraw from the market
                if (targetAssets == 0) {
                    toWithdraw = currentSupplied;
                }

                pool.withdraw(address(this), toWithdraw);

                totalWithdrawn += toWithdraw;

                emit ReallocateWithdraw(pool, toWithdraw);
            } else {
                // if `targetAsset` is `type(uint256).max`, then supply all
                // assets that have been withdrawn but not yet supplied so far
                // in the for loop into this market.
                uint256 toSupply = targetAssets == type(uint256).max
                    ? _zeroFloorSub(totalWithdrawn, totalSupplied)
                    : _zeroFloorSub(targetAssets, currentSupplied);

                if (toSupply == 0) continue;

                if (currentSupplied + toSupply > caps[pool]) revert AllocationCapExceeded();

                pool.supply(address(this), toSupply, new bytes32[](0));

                totalSupplied += toSupply;

                emit ReallocateSupply(pool, toSupply);
            }
        }

        if (totalWithdrawn != totalSupplied) revert InvalidReallocation();
    }

    // --- IonPool Interactions ---

    function _supplyToIonPool(uint256 assets) internal {
        for (uint256 i; i < supplyQueue.length; ++i) {
            IonPool pool = supplyQueue[i];

            console2.log("i: ", i);
            console2.log("pool: ", pool);

            uint256 supplyCap = caps[pool];
            if (supplyCap == 0) continue;

            pool.accrueInterest();

            // supply as much assets we can to fill the cap for each market
            uint256 currentSupplied = pool.balanceOf(address(this));
            uint256 toSupply = Math.min(_zeroFloorSub(supplyCap, currentSupplied), assets);
            if (toSupply > 0) {
                pool.supply(address(this), toSupply, new bytes32[](0));
                assets -= toSupply; // `supply` might take 1 more wei than expected
            }
            if (assets == 0) return;
        }
        if (assets != 0) revert AllSupplyCapsReached();
    }

    function _withdrawFromIonPool(uint256 assets) internal {
        for (uint256 i; i < supplyQueue.length; ++i) {
            IonPool pool = withdrawQueue[i];

            uint256 currentSupplied = pool.balanceOf(address(this));
            uint256 toWithdraw = Math.min(currentSupplied, assets);

            // If `assets` is greater than `currentSupplied`, we want to fully withdraw from this market.
            // In IonPool, the shares to burn is rounded up as
            // ceil(assets / supplyFactor)
            if (toWithdraw > 0) {
                pool.withdraw(address(this), toWithdraw);
                assets -= toWithdraw;
            }
            if (assets == 0) return;
        }

        if (assets != 0) revert NotEnoughLiquidityToWithdraw();
    }

    function _accrueFee() internal returns (uint256 newTotalAssets) {
        uint256 feeShares;
        (feeShares, newTotalAssets) = _accruedFeeShares();
        if (feeShares != 0) _mint(feeRecipient, feeShares);

        lastTotalAssets = newTotalAssets; // This update happens outside of this function in Metamorpho.

        emit FeeAccrued(feeShares, newTotalAssets);
    }

    /**
     * @dev The total accrued vault revenue is the difference in the total iToken holdings from the last accrued
     * timestamp.
     */
    function _accruedFeeShares() internal view returns (uint256 feeShares, uint256 newTotalAssets) {
        newTotalAssets = totalAssets();
        uint256 totalInterest = _zeroFloorSub(newTotalAssets, lastTotalAssets);

        // totalInterest amount of new iTokens were created for this vault
        // a portion of this should be claimable by depositors
        // a portion of this should be claimable by the fee recipient
        if (totalInterest != 0 && feePercentage != 0) {
            uint256 feeAssets = totalInterest.mulDiv(feePercentage, WAD);

            feeShares =
                _convertToSharesWithTotals(feeAssets, totalSupply(), newTotalAssets - feeAssets, Math.Rounding.Floor);
        }
    }

    /**
     * @notice Returns the total claim that the vault has across all supported IonPools.
     * @dev `IonPool.balanceOf` returns the rebasing balance of the lender receipt token that is pegged 1:1 to the
     * underlying supplied asset.
     */
    function totalAssets() public view override returns (uint256 assets) {
        for (uint256 i; i < supportedMarkets.length(); ++i) {
            assets += IonPool(supportedMarkets.at(i)).balanceOf(address(this));
        }
    }

    /**
     * @dev Returns the amount of shares that the vault would exchange for the amount of `assets` provided.
     */
    function _convertToSharesWithTotals(
        uint256 assets,
        uint256 newTotalSupply,
        uint256 newTotalAssets,
        Math.Rounding rounding
    )
        internal
        view
        returns (uint256)
    {
        return assets.mulDiv(newTotalSupply + 10 ** _decimalsOffset(), newTotalAssets + 1, rounding);
    }

    function _updateLastTotalAssets(uint256 newLastTotalAssets) internal {
        lastTotalAssets = newLastTotalAssets;
        emit UpdateLastTotalAssets(lastTotalAssets, newLastTotalAssets);
    }

    function _zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }

    function getSupportedMarkets() external view returns (address[] memory) {
        return supportedMarkets.values();
    }
}
