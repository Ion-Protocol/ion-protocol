// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { IIonPool } from "./../interfaces/IIonPool.sol";
import { IIonPool } from "./../interfaces/IIonPool.sol";
import { RAY } from "./../libraries/math/WadRayMath.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
/**
 * @title Ion Lending Vault
 * @author Molecular Labs
 * @notice Vault contract that can allocate a single lender asset over various
 * isolated lending pairs on Ion Protocol. This contract is a fork of the
 * Metamorpho contract licnesed under GPL-2.0 with changes to administrative
 * logic, underlying data structures, and lending interactions to be made
 * compatible with Ion Protocol.
 *
 * @custom:security-contact security@molecularlabs.io
 */

contract Vault is ERC4626, Multicall, AccessControlDefaultAdminRules, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Math for uint256;

    error InvalidQueueLength(uint256 queueLength, uint256 supportedMarketsLength);
    error AllocationCapExceeded(uint256 resultingSupplied, uint256 allocationCap);
    error InvalidReallocation(uint256 totalSupplied, uint256 totalWithdrawn);
    error InvalidMarketRemovalNonZeroSupply(IIonPool pool);
    error InvalidUnderlyingAsset(IIonPool pool);
    error MarketAlreadySupported(IIonPool pool);
    error MarketNotSupported(IIonPool pool);
    error AllSupplyCapsReached();
    error NotEnoughLiquidityToWithdraw();
    error InvalidIdleMarketRemovalNonZeroBalance();
    error InvalidQueueContainsDuplicates();
    error MarketsAndAllocationCapLengthMustBeEqual();
    error IonPoolsArrayAndNewCapsArrayMustBeOfEqualLength();
    error InvalidFeePercentage();

    event UpdateSupplyQueue(address indexed caller, IIonPool[] newSupplyQueue);
    event UpdateWithdrawQueue(address indexed caller, IIonPool[] newWithdrawQueue);

    event ReallocateWithdraw(IIonPool indexed pool, uint256 assets);
    event ReallocateSupply(IIonPool indexed pool, uint256 assets);
    event FeeAccrued(uint256 feeShares, uint256 newTotalAssets);
    event UpdateLastTotalAssets(uint256 lastTotalAssets, uint256 newLastTotalAssets);

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    IIonPool public constant IDLE = IIonPool(address(uint160(uint256(keccak256("IDLE_ASSET_HOLDINGS")))));

    uint8 public immutable DECIMALS_OFFSET;

    bytes32 public immutable ION_POOL_SUPPLY_CAP_SLOT =
        0xceba3d526b4d5afd91d1b752bf1fd37917c20a6daf576bcb41dd1c57c1f67e09;
    bytes32 public immutable ION_POOL_LIQUIDITY_SLOT =
        0xceba3d526b4d5afd91d1b752bf1fd37917c20a6daf576bcb41dd1c57c1f67e08;

    IERC20 public immutable BASE_ASSET;

    EnumerableSet.AddressSet supportedMarkets;

    IIonPool[] public supplyQueue;
    IIonPool[] public withdrawQueue;

    address public feeRecipient;
    uint256 public feePercentage; // [RAY]

    uint256 public lastTotalAssets;

    mapping(IIonPool => uint256) public caps;

    struct MarketAllocation {
        IIonPool pool;
        int256 assets;
    }

    struct MarketsArgs {
        IIonPool[] marketsToAdd;
        uint256[] allocationCaps;
        IIonPool[] newSupplyQueue;
        IIonPool[] newWithdrawQueue;
    }

    constructor(
        IERC20 _baseAsset,
        address _feeRecipient,
        uint256 _feePercentage,
        string memory _name,
        string memory _symbol,
        uint48 initialDelay,
        address initialDefaultAdmin,
        MarketsArgs memory marketsArgs
    )
        ERC4626(_baseAsset)
        ERC20(_name, _symbol)
        AccessControlDefaultAdminRules(initialDelay, initialDefaultAdmin)
    {
        BASE_ASSET = _baseAsset;

        feePercentage = _feePercentage;
        feeRecipient = _feeRecipient;

        DECIMALS_OFFSET = uint8(_zeroFloorSub(uint256(18), IERC20Metadata(address(_baseAsset)).decimals()));

        _addSupportedMarkets(
            marketsArgs.marketsToAdd,
            marketsArgs.allocationCaps,
            marketsArgs.newSupplyQueue,
            marketsArgs.newWithdrawQueue
        );
    }

    /**
     * @notice Updates the fee percentage.
     * @dev Input must be in [RAY]. Ex) 2% would be 0.02e27.
     * @param _feePercentage The percentage of the interest accrued to take as a
     * management fee.
     */
    function updateFeePercentage(uint256 _feePercentage) external onlyRole(OWNER_ROLE) {
        if (_feePercentage > RAY) revert InvalidFeePercentage();
        _accrueFee();
        feePercentage = _feePercentage;
    }

    /**
     * @notice Updates the fee recipient.
     * @param _feeRecipient The recipient address of the shares minted as fees.
     */
    function updateFeeRecipient(address _feeRecipient) external onlyRole(OWNER_ROLE) {
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Add markets that can be supplied and withdrawn from.
     * @dev Elements in `supportedMarkets` must be a valid IonPool or an IDLE
     * address. Valid IonPools require the base asset to be the same. Duplicate
     * addition to the EnumerableSet will revert. The allocationCaps of the
     * new markets being introduced must be set.
     * @param marketsToAdd Array of new markets to be added.
     * @param allocationCaps Array of allocation caps for only the markets to be added.
     * @param newSupplyQueue Desired supply queue of IonPools for all resulting supported markets.
     * @param newWithdrawQueue Desired withdraw queue of IonPools for all resulting supported markets.
     */
    function addSupportedMarkets(
        IIonPool[] memory marketsToAdd,
        uint256[] memory allocationCaps,
        IIonPool[] memory newSupplyQueue,
        IIonPool[] memory newWithdrawQueue
    )
        external
        onlyRole(OWNER_ROLE)
    {
        _addSupportedMarkets(marketsToAdd, allocationCaps, newSupplyQueue, newWithdrawQueue);
    }

    function _addSupportedMarkets(
        IIonPool[] memory marketsToAdd,
        uint256[] memory allocationCaps,
        IIonPool[] memory newSupplyQueue,
        IIonPool[] memory newWithdrawQueue
    )
        internal
    {
        if (marketsToAdd.length != allocationCaps.length) revert MarketsAndAllocationCapLengthMustBeEqual();

        for (uint256 i; i != marketsToAdd.length;) {
            IIonPool pool = marketsToAdd[i];

            if (pool != IDLE) {
                if (address(pool.underlying()) != address(BASE_ASSET)) {
                    revert InvalidUnderlyingAsset(pool);
                }
                BASE_ASSET.approve(address(pool), type(uint256).max);
            }

            if (!supportedMarkets.add(address(pool))) revert MarketAlreadySupported(pool);

            caps[pool] = allocationCaps[i];

            unchecked {
                ++i;
            }
        }

        _updateSupplyQueue(newSupplyQueue);
        _updateWithdrawQueue(newWithdrawQueue);
    }

    /**
     * @notice Removes a supported market and updates the supply and withdraw
     * queues without the removed market.
     * @dev The allocationCap values of the markets being removed are
     * automatically deleted. Whenever a market is removed, the queues must be
     * updated without the removed market.
     * @param marketsToRemove Markets being removed.
     * @param newSupplyQueue Desired supply queue of all supported markets after
     * the removal.
     * @param newWithdrawQueue Desired withdraw queue of all supported markets
     * after the removal.
     */
    function removeSupportedMarkets(
        IIonPool[] calldata marketsToRemove,
        IIonPool[] calldata newSupplyQueue,
        IIonPool[] calldata newWithdrawQueue
    )
        external
        onlyRole(OWNER_ROLE)
    {
        for (uint256 i; i != marketsToRemove.length;) {
            IIonPool pool = marketsToRemove[i];

            if (pool == IDLE) {
                if (BASE_ASSET.balanceOf(address(this)) != 0) revert InvalidIdleMarketRemovalNonZeroBalance();
            } else {
                // Checks `normalizedBalanceOf` as it may be possible that
                // `balanceOf` returns zero even though the
                // `normalizedBalance` is zero.
                if (pool.normalizedBalanceOf(address(this)) != 0) revert InvalidMarketRemovalNonZeroSupply(pool);
                BASE_ASSET.approve(address(pool), 0);
            }

            if (!supportedMarkets.remove(address(pool))) revert MarketNotSupported(pool);
            delete caps[pool];

            unchecked {
                ++i;
            }
        }
        _updateSupplyQueue(newSupplyQueue);
        _updateWithdrawQueue(newWithdrawQueue);
    }

    /**
     * @notice Update the order of the markets in which user deposits are supplied.
     * @dev Each IonPool in the queue must be part of the `supportedMarkets` set.
     * @param newSupplyQueue The new supply queue ordering.
     */
    function updateSupplyQueue(IIonPool[] memory newSupplyQueue) external onlyRole(ALLOCATOR_ROLE) {
        _updateSupplyQueue(newSupplyQueue);
    }

    function _updateSupplyQueue(IIonPool[] memory newSupplyQueue) internal {
        _validateQueueInput(newSupplyQueue);

        supplyQueue = newSupplyQueue;

        emit UpdateSupplyQueue(_msgSender(), newSupplyQueue);
    }

    /**
     * @notice Update the order of the markets in which the deposits are withdrawn.
     * @dev The IonPool in the queue must be part of the `supportedMarkets` set.
     * @param newWithdrawQueue The new withdraw queue ordering.
     */
    function updateWithdrawQueue(IIonPool[] memory newWithdrawQueue) external onlyRole(ALLOCATOR_ROLE) {
        _updateWithdrawQueue(newWithdrawQueue);
    }

    function _updateWithdrawQueue(IIonPool[] memory newWithdrawQueue) internal {
        _validateQueueInput(newWithdrawQueue);

        withdrawQueue = newWithdrawQueue;

        emit UpdateWithdrawQueue(_msgSender(), newWithdrawQueue);
    }

    /**
     * @dev The input array contains ordered IonPools.
     * - Must not contain duplicates.
     * - Must be the same length as the `supportedMarkets` array.
     * - Must not contain indices that are out of bounds of the `supportedMarkets` EnumerableSet's underlying array.
     * The above rule enforces that the queue must have all and only the elements in the `supportedMarkets` set.
     * @param queue The queue being validated.
     */
    function _validateQueueInput(IIonPool[] memory queue) internal view {
        uint256 _supportedMarketsLength = supportedMarkets.length();
        uint256 queueLength = queue.length;

        if (queueLength != _supportedMarketsLength) revert InvalidQueueLength(queueLength, _supportedMarketsLength);

        bool[] memory seen = new bool[](queueLength);

        for (uint256 i; i != queueLength;) {
            // If the pool is not supported, this query reverts.
            uint256 index = _supportedMarketsIndexOf(address(queue[i]));

            if (seen[index] == true) revert InvalidQueueContainsDuplicates();

            seen[index] = true;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Update allocation caps for specified IonPools or the IDLE pool.
     * @dev The allocation caps are applied to pools in the order of the array
     * within `supportedMarkets`. The elements inside `ionPools` must exist in
     * `supportedMarkets`. To update the `IDLE` pool, use the `IDLE` constant
     * address.
     * @param ionPools The array of IonPools whose caps will be updated.
     * @param newCaps The array of new allocation caps to be applied.
     */
    function updateAllocationCaps(
        IIonPool[] calldata ionPools,
        uint256[] calldata newCaps
    )
        external
        onlyRole(OWNER_ROLE)
    {
        if (ionPools.length != newCaps.length) revert IonPoolsArrayAndNewCapsArrayMustBeOfEqualLength();

        for (uint256 i; i != ionPools.length;) {
            IIonPool pool = ionPools[i];
            if (!supportedMarkets.contains(address(pool))) revert MarketNotSupported(pool);
            caps[pool] = newCaps[i];

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Reallocates the base asset supply position across the specified
     * IonPools. This call will revert if the resulting allocation in an IonPool
     * violates the pool's supply cap.
     * @dev Depending on the order of deposits and withdrawals to and from
     * markets, the function could revert if there is not enough assets
     * withdrawn to deposit later in the loop. A key invariant is that the total
     * assets withdrawn should be equal to the total assets supplied. Otherwise,
     * revert.
     * - Negative value indicates a withdrawal.
     * - Positive value indicates a supply.
     * @param allocations Array that indicates how much to deposit or withdraw
     * from each market.
     */
    function reallocate(MarketAllocation[] calldata allocations) external onlyRole(ALLOCATOR_ROLE) nonReentrant {
        uint256 totalSupplied;
        uint256 totalWithdrawn;

        uint256 currentIdleDeposits = BASE_ASSET.balanceOf(address(this));
        for (uint256 i; i != allocations.length;) {
            MarketAllocation calldata allocation = allocations[i];
            IIonPool pool = allocation.pool;

            uint256 currentSupplied = pool == IDLE ? currentIdleDeposits : pool.balanceOf(address(this));
            int256 assets = allocation.assets; // to deposit or withdraw

            // if `assets` is `type(int256).min`, this means fully withdraw from the market.
            // This prevents frontrunning in case the market needs to be fully withdrawn
            // from in order to remove the market.
            uint256 transferAmt;
            if (assets < 0) {
                if (assets == type(int256).min) {
                    // The resulting shares from full withdraw must be zero.
                    transferAmt = currentSupplied;
                } else {
                    transferAmt = uint256(-assets);
                }

                // If `IDLE`, the asset is already held by this contract, no
                // need to withdraw from a pool. The asset will be transferred
                // to the user from the previous function scope.
                if (pool != IDLE) {
                    pool.withdraw(address(this), transferAmt);
                } else {
                    currentIdleDeposits -= transferAmt;
                }

                totalWithdrawn += transferAmt;

                emit ReallocateWithdraw(pool, transferAmt);
            } else if (assets > 0) {
                // It is not possible to predict the exact amount of assets that
                // will be withdrawn when using the `type(int256).min` indicator
                // in previous iterations of the loop due to the per-second
                // interest rate accrual. Therefore, the `max` indicator is
                // necessary to be able to fully deposit the total withdrawn
                // amount.
                if (assets == type(int256).max) {
                    transferAmt = totalWithdrawn;
                } else {
                    transferAmt = uint256(assets);
                }

                uint256 resultingSupplied = currentSupplied + transferAmt;
                uint256 allocationCap = caps[pool];
                if (resultingSupplied > allocationCap) {
                    revert AllocationCapExceeded(resultingSupplied, allocationCap);
                }

                // If the assets are being deposited to IDLE, then no need for
                // additional transfers as the balance is already in this
                // contract.
                if (pool != IDLE) {
                    pool.supply(address(this), transferAmt, new bytes32[](0));
                } else {
                    currentIdleDeposits += transferAmt;
                }

                totalSupplied += transferAmt;

                emit ReallocateSupply(pool, transferAmt);
            }

            unchecked {
                ++i;
            }
        }

        if (totalSupplied != totalWithdrawn) revert InvalidReallocation(totalSupplied, totalWithdrawn);
    }

    /**
     * @notice Manually accrues fees and mints shares to the fee recipient.
     */
    function accrueFee() external onlyRole(OWNER_ROLE) returns (uint256 newTotalAssets) {
        return _accrueFee();
    }

    // --- IonPool Interactions ---

    /**
     * @notice Iterates through the supply queue to deposit the desired amount
     * of assets. Reverts if the deposit amount cannot be filled due to the
     * allocation cap or the supply cap.
     * @dev External functions calling this must be non-reentrant in case the
     * underlying IonPool implements callback logic.
     * @param assets The amount of assets that will attempt to be supplied.
     */
    function _supplyToIonPool(uint256 assets) internal {
        // This function is called after the `BASE_ASSET` is transferred to the
        // contract for the supply iterations. The `assets` is subtracted to
        // retrieve the `BASE_ASSET` balance before this transaction began.
        uint256 currentIdleDeposits = BASE_ASSET.balanceOf(address(this)) - assets;
        uint256 supplyQueueLength = supplyQueue.length;

        for (uint256 i; i != supplyQueueLength;) {
            IIonPool pool = supplyQueue[i];

            uint256 depositable = pool == IDLE ? _zeroFloorSub(caps[pool], currentIdleDeposits) : _depositable(pool);

            if (depositable != 0) {
                uint256 toSupply = Math.min(depositable, assets);

                // For the IDLE pool, decrement the accumulator at the end of this
                // loop, but no external interactions need to be made as the assets
                // are already on this contract' balance.
                if (pool != IDLE) {
                    pool.supply(address(this), toSupply, new bytes32[](0));
                }

                assets -= toSupply;
                if (assets == 0) return;
            }

            unchecked {
                ++i;
            }
        }
        if (assets != 0) revert AllSupplyCapsReached();
    }

    /**
     * @notice Iterates through the withdraw queue to withdraw the desired
     * amount of assets. Will revert if there is not enough liquidity or if
     * trying to withdraw more than the caller owns.
     * @dev External functions calling this must be non-reentrant in case the
     * underlying IonPool implements callback logic.
     * @param assets The desired amount of assets to be withdrawn.
     */
    function _withdrawFromIonPool(uint256 assets) internal {
        uint256 currentIdleDeposits = BASE_ASSET.balanceOf(address(this));
        uint256 withdrawQueueLength = withdrawQueue.length;

        for (uint256 i; i != withdrawQueueLength;) {
            IIonPool pool = withdrawQueue[i];

            uint256 withdrawable = pool == IDLE ? currentIdleDeposits : _withdrawable(pool);

            if (withdrawable != 0) {
                uint256 toWithdraw = Math.min(withdrawable, assets);

                // For the `IDLE` pool, they are already on this contract's
                // balance. Update `assets` accumulator but don't actually transfer.
                if (pool != IDLE) {
                    pool.withdraw(address(this), toWithdraw);
                }

                assets -= toWithdraw;
                if (assets == 0) return;
            }

            unchecked {
                ++i;
            }
        }

        if (assets != 0) revert NotEnoughLiquidityToWithdraw();
    }

    // --- ERC4626 External Functions ---

    /**
     * @inheritdoc IERC4626
     * @notice Transfers the specified amount of assets from the sender,
     * supplies into the underlying
     * IonPool markets, and mints a corresponding amount of shares.
     * @dev All incoming deposits are deposited in the order specified in the deposit queue.
     * @param assets Amount of tokens to be deposited.
     * @param receiver The address to receive the minted shares.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        uint256 newTotalAssets = _accrueFee();

        shares = _convertToSharesWithTotals(assets, totalSupply(), newTotalAssets, Math.Rounding.Floor);
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /**
     * @inheritdoc IERC4626
     * @notice Mints the specified amount of shares and deposits a corresponding
     * amount of assets.
     * @dev Converts the shares to assets and iterates through the deposit queue
     * to allocate the deposit across the supported markets.
     * @param shares The exact amount of shares to be minted.
     * @param receiver The address to receive the minted shares.
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        uint256 newTotalAssets = _accrueFee();

        // This is updated again with the deposited assets amount in `_deposit`.
        lastTotalAssets = newTotalAssets;

        assets = _convertToAssetsWithTotals(shares, totalSupply(), newTotalAssets, Math.Rounding.Ceil);

        _deposit(_msgSender(), receiver, assets, shares);
    }

    /**
     * @notice Withdraws specified amount of assets from IonPools and sends them
     * to the receiver in exchange for burning the owner's vault shares.
     * @dev All withdraws are withdrawn in the order specified in the withdraw
     * queue. The owner needs to approve the caller to spend their shares.
     * @param assets The exact amount of assets to be transferred out.
     * @param receiver The receiver of the assets transferred.
     * @param owner The owner of the vault shares.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        uint256 newTotalAssets = _accrueFee();
        shares = _convertToSharesWithTotals(assets, totalSupply(), newTotalAssets, Math.Rounding.Ceil);
        _updateLastTotalAssets(_zeroFloorSub(newTotalAssets, assets));

        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /**
     * @inheritdoc IERC4626
     * @notice Redeems the exact amount of shares and receives a corresponding
     * amount of assets.
     * @dev After withdrawing `assets`, the user gets exact `assets` out. But in
     * the IonPool, the resulting total underlying claim may have decreased
     * by a bit above the `assets` amount due to rounding in the pool's favor.
     *
     * In that case, the resulting `totalAssets()` will be smaller than just
     * the `newTotalAssets - assets`. Predicting the exact resulting
     * totalAssets() requires knowing how much liquidity is being withdrawn
     * from each pool, which is not possible to know until the actual
     * iteration on the withdraw queue. So we acknowledge the dust
     * difference here.
     *
     * If the `lastTotalAssets` is slightly greater than the actual `totalAssets`,
     * the impact will be that the calculated interest accrued during fee distribution will be slightly less than the
     * true value.
     * @param shares The exact amount of shares to be burned and redeemed.
     * @param receiver The address that receives the transferred assets.
     * @param owner The address that holds the shares to be redeemed.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        uint256 newTotalAssets = _accrueFee();

        assets = _convertToAssetsWithTotals(shares, totalSupply(), newTotalAssets, Math.Rounding.Floor);

        _updateLastTotalAssets(newTotalAssets - assets);

        _withdraw(_msgSender(), receiver, owner, assets, shares);
    }

    /**
     * @inheritdoc IERC20Metadata
     */
    function decimals() public view override(ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }

    /**
     * @inheritdoc IERC4626
     * @notice Returns the maximum amount of assets that the vault can supply on
     * Ion.
     * @dev The max deposit amount is limited by the vault's allocation cap and
     * the underlying IonPools' supply caps.
     * @return The max amount of assets that can be supplied.
     */
    function maxDeposit(address) public view override returns (uint256) {
        return _maxDeposit();
    }

    /**
     * @inheritdoc IERC4626
     * @notice Returns the maximum amount of vault shares that can be minted.
     * @dev Max mint is limited by the max deposit based on the Vault's
     * allocation caps and the IonPools' supply caps. The conversion from max
     * suppliable assets to shares preempts the shares minted from fee accrual.
     * @return The max amount of shares that can be minted.
     */
    function maxMint(address) public view override returns (uint256) {
        uint256 suppliable = _maxDeposit();

        return _convertToSharesWithFees(suppliable, Math.Rounding.Floor);
    }

    /**
     * @inheritdoc IERC4626
     * @notice Returns the maximum amount of assets that can be withdrawn.
     * @dev Max withdraw is limited by the owner's shares and the  liquidity
     * available to be withdrawn from the underlying IonPools. The max
     * withdrawable claim is inclusive of accrued interest and the extra shares
     * minted to the fee recipient.
     * @param owner The address that holds the assets.
     * @return assets The max amount of assets that can be withdrawn.
     */
    function maxWithdraw(address owner) public view override returns (uint256 assets) {
        (assets,,) = _maxWithdraw(owner);
    }

    /**
     * @inheritdoc IERC4626
     * @notice Calculates the total withdrawable amount based on the available
     * liquidity in the underlying pools and converts it to redeemable shares.
     * @dev Max redeem is derived from çonverting the `_maxWithdraw` to shares.
     * The conversion takes into account the total supply and total assets
     * inclusive of accrued interest and the extra shares minted to the fee
     * recipient.
     * @param owner The address that holds the shares.
     * @return The max amount of shares that can be withdrawn.
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets) = _maxWithdraw(owner);
        return _convertToSharesWithTotals(assets, newTotalSupply, newTotalAssets, Math.Rounding.Floor);
    }

    /**
     * @notice Returns the total claim that the vault has across all supported IonPools.
     * @dev `IonPool.balanceOf` returns the rebasing balance of the
     * lender receipt token that is pegged 1:1 to the underlying supplied asset.
     * @return assets The total assets held on the contract and inside the underlying
     * pools by this vault.
     */
    function totalAssets() public view override returns (uint256 assets) {
        uint256 _supportedMarketsLength = supportedMarkets.length();
        for (uint256 i; i != _supportedMarketsLength;) {
            IIonPool pool = IIonPool(supportedMarkets.at(i));

            uint256 assetsInPool = pool == IDLE ? BASE_ASSET.balanceOf(address(this)) : pool.balanceOf(address(this));

            assets += assetsInPool;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc IERC4626
     * @dev Inclusive of manager fee.
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return _convertToSharesWithFees(assets, Math.Rounding.Floor);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Inclusive of manager fee.
     */
    function previewMint(uint256 shares) public view override returns (uint256) {
        return _convertToAssetsWithFees(shares, Math.Rounding.Ceil);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Inclusive of manager fee.
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        return _convertToSharesWithFees(assets, Math.Rounding.Ceil);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Inclusive of manager fee.
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return _convertToAssetsWithFees(shares, Math.Rounding.Floor);
    }

    // --- ERC4626 Internal Functions ---

    function _decimalsOffset() internal view override returns (uint8) {
        return DECIMALS_OFFSET;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        _supplyToIonPool(assets);
        _updateLastTotalAssets(lastTotalAssets + assets);
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

    function _maxDeposit() internal view returns (uint256 maxDepositable) {
        for (uint256 i; i != supportedMarkets.length();) {
            IIonPool pool = IIonPool(supportedMarkets.at(i));

            uint256 depositable =
                pool == IDLE ? _zeroFloorSub(caps[pool], BASE_ASSET.balanceOf(address(this))) : _depositable(pool);

            maxDepositable += depositable;

            unchecked {
                ++i;
            }
        }
    }

    function _maxWithdraw(address owner)
        internal
        view
        returns (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets)
    {
        uint256 feeShares;
        (feeShares, newTotalAssets) = _accruedFeeShares();
        newTotalSupply = totalSupply() + feeShares;

        assets = _convertToAssetsWithTotals(balanceOf(owner), newTotalSupply, newTotalAssets, Math.Rounding.Floor);

        assets -= _simulateWithdrawIon(assets);
    }

    // --- Internal ---

    function _accrueFee() internal returns (uint256 newTotalAssets) {
        uint256 feeShares;
        (feeShares, newTotalAssets) = _accruedFeeShares();
        if (feeShares != 0) _mint(feeRecipient, feeShares);

        lastTotalAssets = newTotalAssets;

        emit FeeAccrued(feeShares, newTotalAssets);
    }

    /**
     * @dev The total accrued vault revenue is the difference in the total
     * iToken holdings from the last accrued timestamp and now.
     */
    function _accruedFeeShares() internal view returns (uint256 feeShares, uint256 newTotalAssets) {
        newTotalAssets = totalAssets();
        uint256 totalInterest = _zeroFloorSub(newTotalAssets, lastTotalAssets);

        // The new amount of new iTokens that were created for this vault. A
        // portion of this should be claimable by depositors and some portion of
        // this should be claimable by the fee recipient.
        if (totalInterest != 0 && feePercentage != 0) {
            uint256 feeAssets = totalInterest.mulDiv(feePercentage, RAY);

            feeShares =
                _convertToSharesWithTotals(feeAssets, totalSupply(), newTotalAssets - feeAssets, Math.Rounding.Floor);
        }
    }

    /**
     * @dev NOTE The IERC4626 natspec recommends that the `_convertToAssets` and `_convertToShares` "MUST NOT be
     * inclusive of any fees that are charged against assets in the Vault."
     * However, all deposit/mint/withdraw/redeem flow will accrue fees before
     * processing user requests, so manager fee must be accounted for to accurately reflect the resulting state.
     * All preview functions will rely on this `WithFees` version of the `_convertTo` function.
     */
    function _convertToSharesWithFees(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = _accruedFeeShares();

        return _convertToSharesWithTotals(assets, totalSupply() + feeShares, newTotalAssets, rounding);
    }

    /**
     * @dev NOTE The IERC4626 natspec recommends that the `_convertToAssets` and `_convertToShares` "MUST NOT be
     * inclusive of any fees that are charged against assets in the Vault."
     * However, all deposit/mint/withdraw/redeem flow will accrue fees before
     * processing user requests, so manager fee must be accounted for to accurately reflect the resulting state.
     * All preview functions will rely on this `WithFees` version of the `_convertTo` function.
     */
    function _convertToAssetsWithFees(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = _accruedFeeShares();

        return _convertToAssetsWithTotals(shares, totalSupply() + feeShares, newTotalAssets, rounding);
    }

    /**
     * @dev Returns the amount of shares that the vault would exchange for the
     * amount of `assets` provided. This function is used to calculate the
     * conversion between shares and assets with parameterizable total supply
     * and total assets variables.
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

    /**
     * @dev Returns the amount of assets that the vault would exchange for the
     * amount of `shares` provided. This function is used to calculate the
     * conversion between shares and assets with parameterizable total supply
     * and total assets variables.
     */
    function _convertToAssetsWithTotals(
        uint256 shares,
        uint256 newTotalSupply,
        uint256 newTotalAssets,
        Math.Rounding rounding
    )
        internal
        view
        returns (uint256)
    {
        return shares.mulDiv(newTotalAssets + 1, newTotalSupply + 10 ** _decimalsOffset(), rounding);
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

    /**
     * @dev Emulates the actual `_withdrawFromIonPool` accounting to predict
     * accurately how much of the input assets will be left after withdrawing as much as it can. The
     * difference between this return value and the input `assets` is the exact
     * amount that will be withdrawn.
     * @return The remaining assets to be withdrawn. NOT the amount of assets that were withdrawn.
     */
    function _simulateWithdrawIon(uint256 assets) internal view returns (uint256) {
        uint256 withdrawQueueLength = withdrawQueue.length;
        for (uint256 i; i != withdrawQueueLength;) {
            IIonPool pool = withdrawQueue[i];

            uint256 withdrawable = pool == IDLE ? BASE_ASSET.balanceOf(address(this)) : _withdrawable(pool);

            uint256 toWithdraw = Math.min(withdrawable, assets);
            assets -= toWithdraw;

            if (assets == 0) break;

            unchecked {
                ++i;
            }
        }

        return assets; // the remaining assets after withdraw
    }

    /**
     * @dev The max amount of assets withdrawable from a given IonPool
     * considering the vault's claim and the available liquidity. A minimum of
     * this contract's total claim on the underlying and the available liquidity
     * in the pool.
     * @return The max amount of assets withdrawable from this IonPool.
     */
    function _withdrawable(IIonPool pool) internal view returns (uint256) {
        uint256 currentSupplied = pool.balanceOf(address(this));
        uint256 availableLiquidity = uint256(pool.extsload(ION_POOL_LIQUIDITY_SLOT));

        return Math.min(currentSupplied, availableLiquidity);
    }

    /**
     * @dev The max amount of assets depositable to a given IonPool. Depositing
     * the minimum between the two diffs ensures that the deposit will not
     * violate the allocation cap or the supply cap.
     * @return The max amount of assets depositable to this IonPool.
     */
    function _depositable(IIonPool pool) internal view returns (uint256) {
        uint256 allocationCapDiff = _zeroFloorSub(caps[pool], pool.balanceOf(address(this)));
        uint256 supplyCapDiff = _zeroFloorSub(uint256(pool.extsload(ION_POOL_SUPPLY_CAP_SLOT)), pool.totalSupply());

        return Math.min(allocationCapDiff, supplyCapDiff);
    }

    // --- EnumerableSet.Address Getters ---

    /**
     * @notice Returns the array representation of the `supportedMarkets` set.
     * @return Array of supported IonPools.
     */
    function getSupportedMarkets() external view returns (address[] memory) {
        return supportedMarkets.values();
    }

    /**
     * @notice Returns whether the market is part of the `supportedMarkets` set.
     * @param pool The address of the IonPool to be checked.
     * @return The pool is supported if true. If not, false.
     */
    function containsSupportedMarket(address pool) external view returns (bool) {
        return supportedMarkets.contains(pool);
    }

    /**
     * @notice Returns the element in the array representation of
     * `supportedMarkets`. `index` must be strictly less than the length of the
     * array.
     * @param index The index to be queried on the `supportedMarkets` array.
     * @return Address at the index of `supportedMarkets`.
     */
    function supportedMarketsAt(uint256 index) external view returns (address) {
        return supportedMarkets.at(index);
    }

    /**
     * @notice Returns the index of the specified market in the array representation of `supportedMarkets`.
     * @dev The `_positions` mapping inside the `EnumerableSet.Set` returns the
     * index of the element in the `_values` array plus 1. The `_positions`
     * value of 0 means that the value is not in the set. If the value is not in
     * the set, this call will revert. Otherwise, it will return the `position -
     * 1` value to return the index of the element in the array.
     * @param pool The address of the IonPool to be queried.
     * @return The index of the pool's location in the array. The return value
     * will always be greater than zero as this function would revert if the
     * market is not part of the set.
     */
    function supportedMarketsIndexOf(address pool) external view returns (uint256) {
        return _supportedMarketsIndexOf(pool);
    }

    /**
     * @notice Length of the array representation of `supportedMarkets`.
     * @return The length of the `supportedMarkets` array.
     */
    function supportedMarketsLength() external view returns (uint256) {
        return supportedMarkets.length();
    }

    function _supportedMarketsIndexOf(address pool) internal view returns (uint256) {
        bytes32 key = bytes32(uint256(uint160(pool)));
        uint256 position = supportedMarkets._inner._positions[key];
        if (position == 0) revert MarketNotSupported(IIonPool(pool));
        return --position;
    }
}
