// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.21;

import { IIonPool } from "./../interfaces/IIonPool.sol";
import { IIonPool } from "./../interfaces/IIonPool.sol";
import { IIonLens } from "./../interfaces/IIonLens.sol";
import { RAY } from "./../libraries/math/WadRayMath.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { AccessControlDefaultAdminRules } from
    "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

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

    error InvalidQueueLength();
    error AllocationCapExceeded();
    error AllSupplyCapsReached();
    error NotEnoughLiquidityToWithdraw();
    error InvalidIdleMarketRemovalNonZeroBalance();
    error InvalidMarketRemovalNonZeroSupply();
    error InvalidSupportedMarkets();
    error InvalidQueueContainsDuplicates();
    error MarketsAndAllocationCapLengthMustBeEqual();
    error MarketAlreadySupported();
    error MarketNotSupported();
    error IonPoolsArrayAndNewCapsArrayMustBeOfEqualLength();
    error InvalidReallocation();
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

    IIonLens public immutable ionLens;
    IERC20 public immutable baseAsset;

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

    constructor(
        IIonLens _ionLens,
        IERC20 _baseAsset,
        address _feeRecipient,
        uint256 _feePercentage,
        string memory _name,
        string memory _symbol,
        uint48 initialDelay,
        address initialDefaultAdmin
    )
        ERC4626(_baseAsset)
        ERC20(_name, _symbol)
        AccessControlDefaultAdminRules(initialDelay, initialDefaultAdmin)
    {
        ionLens = _ionLens;
        baseAsset = _baseAsset;

        feePercentage = _feePercentage;
        feeRecipient = _feeRecipient;

        DECIMALS_OFFSET = uint8(_zeroFloorSub(uint256(18), IERC20Metadata(address(_baseAsset)).decimals()));
    }

    /**
     * @notice Updates the fee percentage.
     * @dev Input must be in [RAY]. Ex) 2% would be 0.02e27.
     */
    function updateFeePercentage(uint256 _feePercentage) external onlyRole(OWNER_ROLE) {
        if (_feePercentage > RAY) revert InvalidFeePercentage();
        feePercentage = _feePercentage;
    }

    /**
     * @notice Updates the fee recipient.
     */
    function updateFeeRecipient(address _feeRecipient) external onlyRole(OWNER_ROLE) {
        feeRecipient = _feeRecipient;
    }

    /**
     * @notice Add markets that can be supplied and withdrawn from.
     * @dev Elements in `supportedMarkets` must be a valid IonPool or an IDLE
     * address. Valid IonPools require the base asset to be the same. Duplicate
     * addition to the EnumerableSet will revert. Sets the allocationCaps of the
     * new markets being introduced.
     */
    function addSupportedMarkets(
        IIonPool[] calldata marketsToAdd,
        uint256[] calldata allocationCaps,
        IIonPool[] calldata newSupplyQueue,
        IIonPool[] calldata newWithdrawQueue
    )
        public
        onlyRole(OWNER_ROLE)
    {
        if (marketsToAdd.length != allocationCaps.length) revert MarketsAndAllocationCapLengthMustBeEqual();

        for (uint256 i; i != marketsToAdd.length;) {
            IIonPool pool = marketsToAdd[i];

            if (pool != IDLE) {
                if (address(pool.underlying()) != address(baseAsset)) {
                    revert InvalidSupportedMarkets();
                }
                baseAsset.approve(address(pool), type(uint256).max);
            }

            if (!supportedMarkets.add(address(pool))) revert MarketAlreadySupported();

            caps[pool] = allocationCaps[i];

            unchecked {
                ++i;
            }
        }

        updateSupplyQueue(newSupplyQueue);
        updateWithdrawQueue(newWithdrawQueue);
    }

    /**
     * @notice Removes a supported market and updates the supply/withdraw queues
     * without the removed market.
     * @dev The allocationCap values of the markets being removed are
     * automatically deleted. Whenever a market is removed, the queues must be
     * updated without the removed market.
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
                if (baseAsset.balanceOf(address(this)) != 0) revert InvalidIdleMarketRemovalNonZeroBalance();
            } else {
                // Checks `balanceOf` as it may be possible that
                // `getUnderlyingClaimOf` returns zero even though the
                // `normalizedBalance` is zero.
                if (pool.balanceOf(address(this)) != 0) revert InvalidMarketRemovalNonZeroSupply();
                baseAsset.approve(address(pool), 0);
            }

            if (!supportedMarkets.remove(address(pool))) revert MarketNotSupported();
            delete caps[pool];

            unchecked {
                ++i;
            }
        }
        updateSupplyQueue(newSupplyQueue);
        updateWithdrawQueue(newWithdrawQueue);
    }

    /**
     * @notice Update the order of the markets in which user deposits are supplied.
     * @dev The IonPool in the queue must be part of `supportedMarkets`.
     */
    function updateSupplyQueue(IIonPool[] calldata newSupplyQueue) public onlyRole(ALLOCATOR_ROLE) {
        _validateQueueInput(newSupplyQueue);

        supplyQueue = newSupplyQueue;

        emit UpdateSupplyQueue(_msgSender(), newSupplyQueue);
    }

    /**
     * @notice Update the order of the markets in which the deposits are withdrawn.
     * @dev The IonPool in the queue must be part of `supportedMarkets`.
     */
    function updateWithdrawQueue(IIonPool[] calldata newWithdrawQueue) public onlyRole(ALLOCATOR_ROLE) {
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
     */
    function _validateQueueInput(IIonPool[] memory queue) internal view {
        uint256 _supportedMarketsLength = supportedMarkets.length();
        uint256 queueLength = queue.length;

        if (queueLength != _supportedMarketsLength) revert InvalidQueueLength();

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
     * @dev The allocation caps are applied to pools in the order of the array
     * within `supportedMarkets`. The elements inside `ionPools` must exist in
     * `supportedMarkets`.
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
            if (!supportedMarkets.contains(address(pool))) revert MarketNotSupported();
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
     */
    function reallocate(MarketAllocation[] calldata allocations) external onlyRole(ALLOCATOR_ROLE) nonReentrant {
        uint256 totalSupplied;
        uint256 totalWithdrawn;

        uint256 currentIdleDeposits = baseAsset.balanceOf(address(this));
        for (uint256 i; i != allocations.length;) {
            MarketAllocation calldata allocation = allocations[i];
            IIonPool pool = allocation.pool;

            uint256 currentSupplied = pool == IDLE ? currentIdleDeposits : pool.getUnderlyingClaimOf(address(this));
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

                if (currentSupplied + transferAmt > caps[pool]) {
                    revert AllocationCapExceeded();
                }

                // If the assets are being deposited to IDLE, then no need for
                // additional transfers as the balance is already in this
                // contract.
                if (pool != IDLE) {
                    pool.supply(address(this), transferAmt, new bytes32[](0));
                }

                totalSupplied += transferAmt;

                emit ReallocateSupply(pool, transferAmt);
            }

            unchecked {
                ++i;
            }
        }

        if (totalSupplied != totalWithdrawn) revert InvalidReallocation();
    }

    function accrueFee() external onlyRole(OWNER_ROLE) returns (uint256 newTotalAssets) {
        return _accrueFee();
    }

    // --- IonPool Interactions ---

    /**
     * @notice Iterates through the supply queue to deposit as much as possible.
     * Reverts if the deposit amount cannot be filled due to the allocation cap
     * or the supply cap.
     * @dev Must be non-reentrant in case the underlying IonPool implements
     * callback logic.
     */
    function _supplyToIonPool(uint256 assets) internal {
        // This function is called after the `baseAsset` is transferred to the
        // contract for the supply iterations. The `assets` is subtracted to
        // retrieve the `baseAsset` balance before this transaction began.
        uint256 currentIdleDeposits = baseAsset.balanceOf(address(this)) - assets;
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

    function _withdrawFromIonPool(uint256 assets) internal {
        uint256 currentIdleDeposits = baseAsset.balanceOf(address(this));
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
     * @notice Receives deposits from the sender and supplies into the underlying IonPool markets.
     * @dev All incoming deposits are deposited in the order specified in the deposit queue.
     */
    function deposit(uint256 assets, address receiver) public override nonReentrant returns (uint256 shares) {
        uint256 newTotalAssets = _accrueFee();

        shares = _convertToSharesWithTotals(assets, totalSupply(), newTotalAssets, Math.Rounding.Floor);
        _deposit(_msgSender(), receiver, assets, shares);
    }

    /**
     * @inheritdoc IERC4626
     * @dev
     */
    function mint(uint256 shares, address receiver) public override nonReentrant returns (uint256 assets) {
        uint256 newTotalAssets = _accrueFee();

        // This is updated again with the deposited assets amount in `_deposit`.
        lastTotalAssets = newTotalAssets;

        assets = _convertToAssetsWithTotals(shares, totalSupply(), newTotalAssets, Math.Rounding.Ceil);

        _deposit(_msgSender(), receiver, assets, shares);
    }

    /**
     * @notice Withdraws supplied assets from IonPools and sends them to the receiver in exchange for vault shares.
     * @dev All withdraws are withdrawn in the order specified in the withdraw queue.
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

    function decimals() public view override(ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }

    /**
     * @inheritdoc ERC4626
     * @dev Returns the maximum amount of assets that the vault can supply on Ion.
     */
    function maxDeposit(address) public view override returns (uint256) {
        return _maxDeposit();
    }

    /**
     * @inheritdoc IERC4626
     * @dev Max mint is limited by the max deposit based on the Vault's
     * allocation caps and the IonPools' supply caps. The conversion from max
     * suppliable assets to shares preempts the shares minted from fee accrual.
     */
    function maxMint(address) public view override returns (uint256) {
        uint256 suppliable = _maxDeposit();

        return _convertToSharesWithFees(suppliable, Math.Rounding.Floor);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Max withdraw is limited by the liquidity available to be withdrawn from the underlying IonPools.
     * The max withdrawable claim is inclusive of accrued interest and the extra shares minted to the fee recipient.
     */
    function maxWithdraw(address owner) public view override returns (uint256 assets) {
        (assets,,) = _maxWithdraw(owner);
    }

    /**
     * @inheritdoc IERC4626
     * @dev Max redeem is derived from çonverting the max withdraw to shares.
     * The conversion takes into account the total supply and total assets inclusive of accrued interest and the extra
     * shares minted to the fee recipient.
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets) = _maxWithdraw(owner);
        return _convertToSharesWithTotals(assets, newTotalSupply, newTotalAssets, Math.Rounding.Floor);
    }

    /**
     * @notice Returns the total claim that the vault has across all supported IonPools.
     * @dev `IonPool.getUnderlyingClaimOf` returns the rebasing balance of the
     * lender receipt token that is pegged 1:1 to the underlying supplied asset.
     */
    function totalAssets() public view override returns (uint256 assets) {
        uint256 _supportedMarketsLength = supportedMarkets.length();
        for (uint256 i; i != _supportedMarketsLength;) {
            IIonPool pool = IIonPool(supportedMarkets.at(i));

            uint256 assetsInPool =
                pool == IDLE ? baseAsset.balanceOf(address(this)) : pool.getUnderlyingClaimOf(address(this));

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
                pool == IDLE ? _zeroFloorSub(caps[pool], baseAsset.balanceOf(address(this))) : _depositable(pool);

            maxDepositable += depositable;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Takes the current shares balance of the owner and returns how much assets can be withdrawn considering the
     * available liquidity.
     */
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

        lastTotalAssets = newTotalAssets; // This update happens outside of this function in Metamorpho.

        emit FeeAccrued(feeShares, newTotalAssets);
    }

    /**
     * @dev The total accrued vault revenue is the difference in the total
     * iToken holdings from the last accrued timestamp.
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

    function _convertToSharesWithFees(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        (uint256 feeShares, uint256 newTotalAssets) = _accruedFeeShares();

        return _convertToSharesWithTotals(assets, totalSupply() + feeShares, newTotalAssets, rounding);
    }

    /**
     * @dev NOTE The IERC4626 natspec recomments that the `_convertToAssets` and `_convertToShares` "MUST NOT be
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
     * amount of `assets` provided.
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

            uint256 withdrawable = pool == IDLE ? baseAsset.balanceOf(address(this)) : _withdrawable(pool);

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
     */
    function _withdrawable(IIonPool pool) internal view returns (uint256) {
        uint256 currentSupplied = pool.getUnderlyingClaimOf(address(this));
        uint256 availableLiquidity = ionLens.liquidity(pool);

        return Math.min(currentSupplied, availableLiquidity);
    }

    /**
     * @dev The max amount of assets depositable to a given IonPool. Depositing
     * the minimum between the two diffs ensures that the deposit will not
     * violate the allocation cap or the supply cap.
     */
    function _depositable(IIonPool pool) internal view returns (uint256) {
        uint256 allocationCapDiff = _zeroFloorSub(caps[pool], pool.getUnderlyingClaimOf(address(this)));
        uint256 supplyCapDiff = _zeroFloorSub(ionLens.supplyCap(pool), pool.getTotalUnderlyingClaims());

        return Math.min(allocationCapDiff, supplyCapDiff);
    }

    // --- EnumerableSet.Address Getters ---
    function getSupportedMarkets() external view returns (address[] memory) {
        return supportedMarkets.values();
    }

    function containsSupportedMarket(address pool) external view returns (bool) {
        return supportedMarkets.contains(pool);
    }

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
     * @return The index of the pool's location in the array. The return value
     * will always be greater than zero as this function would revert if the
     * market is not part of the set.
     */
    function supportedMarketsIndexOf(address pool) external view returns (uint256) {
        return _supportedMarketsIndexOf(pool);
    }

    function supportedMarketsLength() external view returns (uint256) {
        return supportedMarkets.length();
    }

    function _supportedMarketsIndexOf(address pool) internal view returns (uint256) {
        bytes32 key = bytes32(uint256(uint160(pool)));
        uint256 position = supportedMarkets._inner._positions[key];
        if (position == 0) revert MarketNotSupported();
        return --position;
    }
}
