// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Whitelist } from "src/Whitelist.sol";
import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";
import { RewardModule } from "src/reward/RewardModule.sol";
import { InterestRate } from "src/InterestRate.sol";
import { WadRayMath, RAY } from "src/libraries/math/WadRayMath.sol";
import { IonPausableUpgradeable } from "src/admin/IonPausableUpgradeable.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract IonPool is IonPausableUpgradeable, RewardModule {
    using SafeERC20 for IERC20;
    using SafeCast for *;
    using WadRayMath for *;
    using Math for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // --- Errors ---
    error CeilingExceeded(uint256 newDebt, uint256 debtCeiling);
    error UnsafePositionChange(uint256 newTotalDebtInVault, uint256 collateral, uint256 spot);
    error UnsafePositionChangeWithoutConsent(uint8 ilkIndex, address user, address unconsentedOperator);
    error GemTransferWithoutConsent(uint8 ilkIndex, address user, address unconsentedOperator);
    error UseOfCollateralWithoutConsent(uint8 ilkIndex, address depositor, address unconsentedOperator);
    error TakingWethWithoutConsent(address payer, address unconsentedOperator);
    error VaultCannotBeDusty(uint256 amountLeft, uint256 dust);
    error ArithmeticError();
    error SpotUpdaterNotAuthorized();
    error IlkAlreadyAdded(address ilkAddress);
    error IlkNotInitialized(uint256 ilkIndex);
    error DepositSurpassesSupplyCap(uint256 depositAmount, uint256 supplyCap);

    error InvalidIlkAddress();
    error InvalidInterestRateModule(InterestRate invalidInterestRateModule);
    error InvalidWhitelist(Whitelist invalidWhitelist);

    // --- Events ---
    event IlkInitialized(uint8 indexed ilkIndex, address indexed ilkAddress);
    event IlkSpotUpdated(address newSpot);
    event IlkDebtCeilingUpdated(uint256 newDebtCeiling);
    event IlkDustUpdated(uint256 newDust);
    event SupplyCapUpdated(uint256 newSupplyCap);
    event InterestRateModuleUpdated(address newModule);
    event WhitelistUpdated(address newWhitelist);

    event AddOperator(address indexed from, address indexed to);
    event RemoveOperator(address indexed from, address indexed to);
    event MintAndBurnGem(uint8 indexed ilkIndex, address indexed usr, int256 wad);
    event TransferGem(uint8 indexed ilkIndex, address indexed src, address indexed dst, uint256 wad);

    /**
     * @dev Emitted when minting for `user` in exchange for `amount` underlying
     * tokens from `underlyingFrom`. `supplyFactor` is the  supply factor at the
     * time and `newDebt` is the debt at the time.
     */
    event Supply(
        address indexed user, address indexed underlyingFrom, uint256 amount, uint256 supplyFactor, uint256 newDebt
    );

    /**
     * @dev Emitted when burning by `user` in exchange for `amount`
     * underlying tokens redeemed to `target`. `supplyFactor` is the  supply
     * factor at the time and `newDebt` is the debt at the time.
     */
    event Withdraw(address indexed user, address indexed target, uint256 amount, uint256 supplyFactor, uint256 newDebt);

    event WithdrawCollateral(uint8 indexed ilkIndex, address indexed user, address indexed recipient, uint256 amount);
    event DepositCollateral(uint8 indexed ilkIndex, address indexed user, address indexed depositor, uint256 amount);
    event Borrow(
        uint8 indexed ilkIndex,
        address indexed user,
        address indexed recipient,
        uint256 amountOfNormalizedDebt,
        uint256 ilkRate,
        uint256 totalDebt
    );
    event Repay(
        uint8 indexed ilkIndex,
        address indexed user,
        address indexed payer,
        uint256 amountOfNormalizedDebt,
        uint256 ilkRate,
        uint256 totalDebt
    );

    event RepayBadDebt(address indexed user, address indexed payer, uint256 rad);
    event ConfiscateVault(
        uint8 indexed ilkIndex,
        address indexed u,
        address v,
        address indexed w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    );

    bytes32 public constant GEM_JOIN_ROLE = keccak256("GEM_JOIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    address private immutable ADDRESS_THIS = address(this);

    // --- Modifiers ---
    modifier onlyWhitelistedBorrowers(uint8 ilkIndex, bytes32[] memory proof) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        $.whitelist.isWhitelistedBorrower(ilkIndex, _msgSender(), proof);
        _;
    }

    modifier onlyWhitelistedLenders(bytes32[] memory proof) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        $.whitelist.isWhitelistedLender(_msgSender(), proof);
        _;
    }

    // --- Data ---
    struct Ilk {
        uint104 totalNormalizedDebt; // Total Normalised Debt     [wad]
        uint104 rate; // Accumulated Rates         [ray]
        uint48 lastRateUpdate; // block.timestamp of last update; overflows in 800_000 years
        SpotOracle spot; // Oracle that provides price with safety margin
        uint256 debtCeiling; // Debt Ceiling              [rad]
        uint256 dust; // Vault Debt Floor            [rad]
    }

    struct Vault {
        uint256 collateral; // Locked Collateral  [wad]
        uint256 normalizedDebt; // Normalised Debt    [wad]
    }

    struct IonPoolStorage {
        Ilk[] ilks;
        // remove() should never be called, it will mess up the ordering
        EnumerableSet.AddressSet ilkAddresses;
        mapping(uint256 ilkIndex => mapping(address user => Vault)) vaults;
        mapping(uint256 ilkIndex => mapping(address user => uint256)) gem; // [wad]
        mapping(address => uint256) unbackedDebt; // [rad]
        mapping(address => mapping(address => uint256)) isOperator;
        uint256 debt; // Total Debt [rad]
        uint256 weth; // liquidity in pool [wad]
        uint256 wethSupplyCap; // [wad]
        uint256 totalUnbackedDebt; // Total Unbacked Dai  [rad]
        InterestRate interestRateModule;
        Whitelist whitelist;
    }

    // keccak256(abi.encode(uint256(keccak256("ion.storage.IonPool")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line
    bytes32 private constant IonPoolStorageLocation = 0xceba3d526b4d5afd91d1b752bf1fd37917c20a6daf576bcb41dd1c57c1f67e00;

    function _getIonPoolStorage() internal pure returns (IonPoolStorage storage $) {
        assembly {
            $.slot := IonPoolStorageLocation
        }
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _underlying,
        address _treasury,
        uint8 decimals_,
        string memory name_,
        string memory symbol_,
        address initialDefaultAdmin,
        InterestRate _interestRateModule,
        Whitelist _whitelist
    )
        external
        initializer
    {
        __AccessControlDefaultAdminRules_init(0, initialDefaultAdmin);
        RewardModule.initialize(_underlying, _treasury, decimals_, name_, symbol_);

        _grantRole(ION, initialDefaultAdmin);

        IonPoolStorage storage $ = _getIonPoolStorage();

        $.interestRateModule = _interestRateModule;
        $.whitelist = _whitelist;

        emit InterestRateModuleUpdated(address(_interestRateModule));
        emit WhitelistUpdated(address(_whitelist));
    }

    // --- Administration ---

    function initializeIlk(address ilkAddress) external onlyRole(ION) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        if (ilkAddress == address(0)) revert InvalidIlkAddress();
        if (!$.ilkAddresses.add(ilkAddress)) revert IlkAlreadyAdded(ilkAddress);

        // Unsafe cast OK since we don't plan on having more than 256
        // collaterals
        uint8 ilkIndex = uint8($.ilks.length);
        Ilk memory newIlk;
        $.ilks.push(newIlk);
        Ilk storage ilk = $.ilks[ilkIndex];

        ilk.rate = 10 ** 27;
        // Unsafe cast OK
        ilk.lastRateUpdate = uint48(block.timestamp);

        emit IlkInitialized(ilkIndex, ilkAddress);
    }

    function updateIlkSpot(uint8 ilkIndex, SpotOracle newSpot) external onlyRole(ION) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.ilks[ilkIndex].spot = newSpot;

        emit IlkSpotUpdated(address(newSpot));
    }

    function updateIlkDebtCeiling(uint8 ilkIndex, uint256 newCeiling) external onlyRole(ION) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.ilks[ilkIndex].debtCeiling = newCeiling;

        emit IlkDebtCeilingUpdated(newCeiling);
    }

    function updateIlkDust(uint8 ilkIndex, uint256 newDust) external onlyRole(ION) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.ilks[ilkIndex].dust = newDust;

        emit IlkDustUpdated(newDust);
    }

    function updateSupplyCap(uint256 newSupplyCap) external onlyRole(ION) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.wethSupplyCap = newSupplyCap;

        emit SupplyCapUpdated(newSupplyCap);
    }

    function updateInterestRateModule(InterestRate _interestRateModule) external onlyRole(ION) {
        if (address(_interestRateModule) == address(0)) revert InvalidInterestRateModule(_interestRateModule);

        IonPoolStorage storage $ = _getIonPoolStorage();

        // Sanity check
        if (_interestRateModule.collateralCount() != $.ilks.length) {
            revert InvalidInterestRateModule(_interestRateModule);
        }
        $.interestRateModule = _interestRateModule;

        emit InterestRateModuleUpdated(address(_interestRateModule));
    }

    function updateWhitelist(Whitelist _whitelist) external onlyRole(ION) {
        if (address(_whitelist) == address(0)) revert InvalidWhitelist(_whitelist);

        IonPoolStorage storage $ = _getIonPoolStorage();

        $.whitelist = _whitelist;

        emit WhitelistUpdated(address(_whitelist));
    }

    /**
     * @dev Pause actions that put the protocol into a further unsafe state.
     * These are actions that take liquidity out of the system (e.g. borrowing,
     * withdrawing base)
     */
    function pauseUnsafeActions() external onlyRole(ION) {
        _pause(Pauses.UNSAFE);
    }

    /**
     * @dev Unpause actions that put the protocol into a further unsafe state.
     */
    function unpauseUnsafeActions() external onlyRole(ION) {
        _unpause(Pauses.UNSAFE);
    }

    /**
     * @dev Pause actions that put the protocol into a further safe state.
     * These are actions that put liquidity into the system (e.g. repaying,
     * depositing base)
     *
     * Pausing accrual is also necessary with this since disabling repaying
     * should not continue to accrue interest.
     *
     * Also accrues interest before the pause to update all debt at the time the
     * pause takes place.
     */
    function pauseSafeActions() external onlyRole(ION) {
        _pause(Pauses.SAFE);
        _accrueInterest();
    }

    /**
     * @dev Unpause actions that put the protocol into a further safe state.
     *
     * Will also update the `lastRateUpdate` to the unpause transaction
     * timestamp. This essentially allows for a pausing and unpausing of the
     * accrual of interest.
     */
    function unpauseSafeActions() external onlyRole(ION) {
        _unpause(Pauses.SAFE);
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 ilksLength = $.ilks.length;
        for (uint256 i = 0; i < ilksLength;) {
            // Unsafe cast OK
            $.ilks[i].lastRateUpdate = uint48(block.timestamp);

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }
    }

    // --- Interest Calculations ---

    function accrueInterest() external whenNotPaused(Pauses.SAFE) returns (uint256 newDebt) {
        return _accrueInterest();
    }

    function _accrueInterest() internal returns (uint256 newTotalDebt) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        // Safe actions should really only be paused in conjunction with unsafe
        // actions. However, if for some reason only safe actions were unpaused,
        // it would still be possible to accrue interest by withdrawing and/or
        // borrowing... so we prevent this outcome; but without reverting the tx
        // altogether.
        if (paused(Pauses.SAFE)) return ($.debt);
        uint256 totalEthSupply = totalSupply();

        uint256 totalSupplyFactorIncrease;
        uint256 totalTreasuryMintAmount;
        uint256 totalDebtIncrease;

        uint256 ilksLength = $.ilks.length;
        for (uint8 i = 0; i < ilksLength;) {
            (
                uint256 supplyFactorIncrease,
                uint256 treasuryMintAmount,
                uint104 newRateIncrease,
                uint256 newDebtIncrease,
                uint48 timestampIncrease
            ) = _calculateRewardAndDebtDistribution(i, totalEthSupply);

            if (timestampIncrease > 0) {
                Ilk storage ilk = $.ilks[i];
                ilk.rate += newRateIncrease;
                ilk.lastRateUpdate += timestampIncrease;
                totalDebtIncrease += newDebtIncrease;

                totalSupplyFactorIncrease += supplyFactorIncrease;
                totalTreasuryMintAmount += treasuryMintAmount;
            }

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }

        newTotalDebt = $.debt + totalDebtIncrease;
        $.debt = newTotalDebt;
        _setSupplyFactor(supplyFactor() + totalSupplyFactorIncrease);
        _mintToTreasury(totalTreasuryMintAmount);
    }

    function _accrueInterestForIlk(uint8 ilkIndex) internal {
        (
            uint256 supplyFactorIncrease,
            uint256 treasuryMintAmount,
            uint104 newRateIncrease,
            uint256 newDebtIncrease,
            uint48 timestampIncrease
        ) = _calculateRewardAndDebtDistribution(ilkIndex, totalSupply());

        IonPoolStorage storage $ = _getIonPoolStorage();

        if (timestampIncrease > 0) {
            Ilk storage ilk = $.ilks[ilkIndex];
            ilk.rate += newRateIncrease;
            ilk.lastRateUpdate += timestampIncrease;
            uint256 newTotalDebt = $.debt + newDebtIncrease;
            $.debt = newTotalDebt;

            _setSupplyFactor(supplyFactor() + supplyFactorIncrease);
            _mintToTreasury(treasuryMintAmount);
        }
    }

    // TODO: Calculate timestamp increase first, then run this function. That way, unecessary computation is avoided
    function _calculateRewardAndDebtDistribution(
        uint8 ilkIndex,
        uint256 totalEthSupply
    )
        internal
        view
        returns (
            uint256 supplyFactorIncrease,
            uint256 treasuryMintAmount,
            uint104 newRateIncrease,
            uint256 newDebtIncrease,
            uint48 timestampIncrease
        )
    {
        IonPoolStorage storage $ = _getIonPoolStorage();
        Ilk storage ilk = $.ilks[ilkIndex];

        uint256 _totalNormalizedDebt = ilk.totalNormalizedDebt;
        // Unsafe cast OK
        if (_totalNormalizedDebt == 0 || block.timestamp == ilk.lastRateUpdate) {
            return (0, 0, 0, 0, 0);
        }
        uint256 totalDebt = _totalNormalizedDebt * ilk.rate; // [WAD] * [RAY] = [RAD]

        (uint256 borrowRate, uint256 reserveFactor) =
            $.interestRateModule.calculateInterestRate(ilkIndex, totalDebt, totalEthSupply);

        if (borrowRate == 0) return (0, 0, 0, 0, 0);

        uint256 borrowRateExpT = _rpow(borrowRate + RAY, block.timestamp - ilk.lastRateUpdate, RAY);

        // Unsafe cast OK
        timestampIncrease = uint48(block.timestamp) - ilk.lastRateUpdate;

        // Debt distribution
        newRateIncrease = ilk.rate.rayMulUp(borrowRateExpT - RAY).toUint104(); // [RAY]

        newDebtIncrease = _totalNormalizedDebt * newRateIncrease; // [RAD]

        // Income distribution
        uint256 _normalizedTotalSupply = normalizedTotalSupply(); // [WAD]

        // If there is no supply, then nothing is being lent out.
        supplyFactorIncrease = _normalizedTotalSupply == 0
            ? 0
            : newDebtIncrease.mulDiv(RAY - reserveFactor, _normalizedTotalSupply.scaleUpToRad(18)); // [RAD] * [RAY] / [RAD]
            // = [RAY]

        treasuryMintAmount = newDebtIncrease.mulDiv(reserveFactor, 1e54); // [RAD] * [RAY] / 1e54 = [WAD]
    }

    // --- Lender Operations ---
    function withdraw(address receiverOfUnderlying, uint256 amount) external whenNotPaused(Pauses.UNSAFE) {
        uint256 newTotalDebt = _accrueInterest();
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.weth -= amount;

        // forgefmt: disable-next-line
        uint256 _supplyFactor = _burn({ user: _msgSender(), receiverOfUnderlying: receiverOfUnderlying, amount: amount });

        emit Withdraw(_msgSender(), receiverOfUnderlying, amount, _supplyFactor, newTotalDebt);
    }

    function supply(
        address user,
        uint256 amount,
        bytes32[] calldata proof
    )
        external
        whenNotPaused(Pauses.SAFE)
        onlyWhitelistedLenders(proof)
    {
        uint256 newTotalDebt = _accrueInterest();
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 _supplyCap = $.wethSupplyCap;
        if (($.weth += amount) > _supplyCap) revert DepositSurpassesSupplyCap(amount, _supplyCap);

        uint256 _supplyFactor = _mint({ user: user, senderOfUnderlying: _msgSender(), amount: amount });

        emit Supply(user, _msgSender(), amount, _supplyFactor, newTotalDebt);
    }

    // --- Borrower Operations ---

    function borrow(
        uint8 ilkIndex,
        address user,
        address recipient,
        uint256 amountOfNormalizedDebt,
        bytes32[] calldata proof
    )
        external
        whenNotPaused(Pauses.UNSAFE)
        onlyWhitelistedBorrowers(ilkIndex, proof)
    {
        _accrueInterestForIlk(ilkIndex);
        (uint104 ilkRate, uint256 newDebt) =
            _modifyPosition(ilkIndex, user, address(0), recipient, 0, amountOfNormalizedDebt.toInt256());

        emit Borrow(ilkIndex, user, recipient, amountOfNormalizedDebt, ilkRate, newDebt);
    }

    function repay(
        uint8 ilkIndex,
        address user,
        address payer,
        uint256 amountOfNormalizedDebt
    )
        external
        whenNotPaused(Pauses.SAFE)
    {
        _accrueInterestForIlk(ilkIndex);
        (uint104 ilkRate, uint256 newDebt) =
            _modifyPosition(ilkIndex, user, address(0), payer, 0, -(amountOfNormalizedDebt.toInt256()));

        emit Repay(ilkIndex, user, payer, amountOfNormalizedDebt, ilkRate, newDebt);
    }

    /**
     * @dev Moves collateral from internal `vault.collateral` balances to `gem`
     */
    function withdrawCollateral(
        uint8 ilkIndex,
        address user,
        address recipient,
        uint256 amount
    )
        external
        whenNotPaused(Pauses.UNSAFE)
    {
        _modifyPosition(ilkIndex, user, recipient, address(0), -(amount.toInt256()), 0);

        emit WithdrawCollateral(ilkIndex, user, recipient, amount);
    }

    /**
     * @dev Moves collateral from `gem` balances to internal `vault.collateral`
     */
    function depositCollateral(
        uint8 ilkIndex,
        address user,
        address depositor,
        uint256 amount,
        bytes32[] calldata proof
    )
        external
        whenNotPaused(Pauses.SAFE)
        onlyWhitelistedBorrowers(ilkIndex, proof)
    {
        _modifyPosition(ilkIndex, user, depositor, address(0), amount.toInt256(), 0);

        emit DepositCollateral(ilkIndex, user, depositor, amount);
    }

    // --- CDP Manipulation ---

    function _modifyPosition(
        uint8 ilkIndex,
        address u,
        address v,
        address w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    )
        internal
        returns (uint104 ilkRate, uint256 newTotalDebt)
    {
        IonPoolStorage storage $ = _getIonPoolStorage();

        ilkRate = $.ilks[ilkIndex].rate;
        // ilk has been initialised
        if (ilkRate == 0) revert IlkNotInitialized(ilkIndex);

        Vault memory vault = $.vaults[ilkIndex][u];
        vault.collateral = _add(vault.collateral, changeInCollateral);
        vault.normalizedDebt = _add(vault.normalizedDebt, changeInNormalizedDebt);

        uint104 _totalNormalizedDebt = _add($.ilks[ilkIndex].totalNormalizedDebt, changeInNormalizedDebt).toUint104();

        // Prevent stack too deep
        {
            uint256 newTotalDebtInVault = ilkRate * vault.normalizedDebt;
            // either debt has decreased, or debt ceilings are not exceeded
            if (
                both(
                    changeInNormalizedDebt > 0,
                    uint256(_totalNormalizedDebt) * uint256(ilkRate) > $.ilks[ilkIndex].debtCeiling
                )
            ) {
                revert CeilingExceeded(uint256(_totalNormalizedDebt) * uint256(ilkRate), $.ilks[ilkIndex].debtCeiling);
            }
            uint256 ilkSpot = $.ilks[ilkIndex].spot.getSpot();
            // vault is either less risky than before, or it is safe
            if (
                both(
                    either(changeInNormalizedDebt > 0, changeInCollateral < 0),
                    newTotalDebtInVault > vault.collateral * ilkSpot
                )
            ) revert UnsafePositionChange(newTotalDebtInVault, vault.collateral, ilkSpot);

            // vault is either more safe, or the owner consents
            if (both(either(changeInNormalizedDebt > 0, changeInCollateral < 0), !isAllowed(u, _msgSender()))) {
                revert UnsafePositionChangeWithoutConsent(ilkIndex, u, _msgSender());
            }

            // collateral src consents
            if (both(changeInCollateral > 0, !isAllowed(v, _msgSender()))) {
                revert UseOfCollateralWithoutConsent(ilkIndex, v, _msgSender());
            }
            // debt dst consents
            // Since changeInDebt is no longer being deducted in the form of
            // internal accounting but rather directly in the erc20 WETH form, this
            // contract must also have an approved role for the debt dst address on
            // th erc20 WETH contract. Or else, the transfer will fail.
            if (both(changeInNormalizedDebt < 0, !isAllowed(w, _msgSender()))) {
                revert TakingWethWithoutConsent(w, _msgSender());
            }

            // vault has no debt, or a non-dusty amount
            if (both(vault.normalizedDebt != 0, newTotalDebtInVault < $.ilks[ilkIndex].dust)) {
                revert VaultCannotBeDusty(newTotalDebtInVault, $.ilks[ilkIndex].dust);
            }
        }

        int256 changeInDebt = ilkRate.toInt256() * changeInNormalizedDebt;

        $.gem[ilkIndex][v] = _sub($.gem[ilkIndex][v], changeInCollateral);
        $.vaults[ilkIndex][u] = vault;
        $.ilks[ilkIndex].totalNormalizedDebt = _totalNormalizedDebt;
        newTotalDebt = _add($.debt, changeInDebt);
        $.debt = newTotalDebt;

        // If changeInDebt < 0, it is a repayment and WETH is being transferred
        // into the protocol
        _transferWeth(w, changeInDebt);
    }

    // --- Settlement ---

    /**
     * @dev To be used by protocol to settle bad debt using reserves
     * NOTE: Can pay another user's bad debt with the sender's asset
     * @param user the address that owns the bad debt being paid off
     * @param rad amount of debt to be repaid (45 decimals)
     */
    function repayBadDebt(address user, uint256 rad) external whenNotPaused(Pauses.SAFE) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.unbackedDebt[user] -= rad;
        $.totalUnbackedDebt -= rad;
        $.debt -= rad;

        // Must be negative since it is a repayment
        _transferWeth(_msgSender(), -(rad.toInt256()));

        emit RepayBadDebt(user, _msgSender(), rad);
    }

    // --- Helpers ---

    /**
     * @dev Helper function to deal with borrowing and repaying debt. A positive
     * amount is a borrow while negative amount is a repayment
     * @param user receiver if transfer to, or sender if transfer from
     * @param amount amount to transfer [rad]
     */
    function _transferWeth(address user, int256 amount) internal {
        if (amount == 0) return;
        IonPoolStorage storage $ = _getIonPoolStorage();

        if (amount < 0) {
            uint256 amountUint = uint256(-amount);
            uint256 amountWad = amountUint / RAY;
            if (amountUint % RAY > 0) ++amountWad;

            $.weth += amountWad;
            underlying().safeTransferFrom(user, address(this), amountWad);
        } else {
            // Round down in protocol's favor
            uint256 amountWad = uint256(amount) / RAY;

            $.weth -= amountWad;

            underlying().safeTransfer(user, amountWad);
        }
    }

    // --- CDP Confiscation ---

    /**
     * @dev This function foregoes pausability for pausability at the
     * liquidation module layer
     */
    function confiscateVault(
        uint8 ilkIndex,
        address u,
        address v,
        address w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    )
        external
        onlyRole(LIQUIDATOR_ROLE)
    {
        IonPoolStorage storage $ = _getIonPoolStorage();

        Vault storage vault = $.vaults[ilkIndex][u];
        Ilk storage ilk = $.ilks[ilkIndex];
        uint104 ilkRate = ilk.rate;

        vault.collateral = _add(vault.collateral, changeInCollateral);
        vault.normalizedDebt = _add(vault.normalizedDebt, changeInNormalizedDebt);
        ilk.totalNormalizedDebt = _add(uint256(ilk.totalNormalizedDebt), changeInNormalizedDebt).toUint104();

        // Unsafe cast OK since we know that ilkRate is less than 2^104
        int256 changeInDebt = int256(uint256(ilkRate)) * changeInNormalizedDebt;

        $.gem[ilkIndex][v] = _sub($.gem[ilkIndex][v], changeInCollateral);
        $.unbackedDebt[w] = _sub($.unbackedDebt[w], changeInDebt);
        $.totalUnbackedDebt = _sub($.totalUnbackedDebt, changeInDebt);

        emit ConfiscateVault(ilkIndex, u, v, w, changeInCollateral, changeInNormalizedDebt);
    }

    // --- Fungibility ---

    /**
     * @dev To be called by GemJoin contracts. After a user deposits collateral, credit the user with collateral
     * internally
     * @param ilkIndex collateral
     * @param usr user
     * @param wad amount to add or remove
     */
    function mintAndBurnGem(
        uint8 ilkIndex,
        address usr,
        int256 wad
    )
        external
        whenNotPaused(Pauses.UNSAFE)
        onlyRole(GEM_JOIN_ROLE)
    {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.gem[ilkIndex][usr] = _add($.gem[ilkIndex][usr], wad);

        emit MintAndBurnGem(ilkIndex, usr, wad);
    }

    function transferGem(uint8 ilkIndex, address src, address dst, uint256 wad) external whenNotPaused(Pauses.UNSAFE) {
        if (!isAllowed(src, _msgSender())) revert GemTransferWithoutConsent(ilkIndex, src, _msgSender());

        IonPoolStorage storage $ = _getIonPoolStorage();

        $.gem[ilkIndex][src] -= wad;
        $.gem[ilkIndex][dst] += wad;
        emit TransferGem(ilkIndex, src, dst, wad);
    }

    // --- Getters ---

    function ilkCount() public view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks.length;
    }

    function getIlkIndex(address ilkAddress) public view returns (uint8) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        bytes32 addressInBytes32 = bytes32(uint256(uint160(ilkAddress)));

        // Since there should never be more than 256 collaterals, an unsafe cast
        // should be fine
        return uint8($.ilkAddresses._inner._positions[addressInBytes32] - 1);
    }

    function getIlkAddress(uint256 ilkIndex) public view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilkAddresses.at(ilkIndex);
    }

    function addressContains(address ilk) public view returns (bool) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilkAddresses.contains(ilk);
    }

    function addressesLength() public view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilkAddresses.length();
    }

    function totalNormalizedDebt(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].totalNormalizedDebt;
    }

    function rate(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].rate;
    }

    function lastRateUpdate(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].lastRateUpdate;
    }

    function spot(uint8 ilkIndex) external view returns (SpotOracle) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].spot;
    }

    function debtCeiling(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].debtCeiling;
    }

    function dust(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].dust;
    }

    function collateral(uint8 ilkIndex, address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.vaults[ilkIndex][user].collateral;
    }

    function normalizedDebt(uint8 ilkIndex, address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.vaults[ilkIndex][user].normalizedDebt;
    }

    function vault(uint8 ilkIndex, address user) external view returns (uint256, uint256) { 
        IonPoolStorage storage $ = _getIonPoolStorage(); 
        return ($.vaults[ilkIndex][user].collateral, $.vaults[ilkIndex][user].normalizedDebt);    
    }

    function gem(uint8 ilkIndex, address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.gem[ilkIndex][user];
    }

    function unbackedDebt(address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.unbackedDebt[user];
    }

    function isOperator(address user, address operator) external view returns (bool) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.isOperator[user][operator] == 1;
    }

    function isAllowed(address bit, address usr) public view returns (bool) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        return either(bit == usr, $.isOperator[bit][usr] == 1);
    }

    function debt() external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.debt;
    }

    function totalUnbackedDebt() external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.totalUnbackedDebt;
    }

    function interestRateModule() external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return address($.interestRateModule);
    }

    function whitelist() external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return address($.whitelist);
    }

    function weth() external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.weth;
    }

    function getCurrentBorrowRate(uint8 ilkIndex) public view returns (uint256 borrowRate, uint256 reserveFactor) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 totalEthSupply = totalSupply();
        uint256 _totalNormalizedDebt = $.ilks[ilkIndex].totalNormalizedDebt;
        uint256 _rate = $.ilks[ilkIndex].rate;

        uint256 totalDebt = _totalNormalizedDebt * _rate; // [WAD] * [RAY] / [WAD] = [RAY]

        (borrowRate, reserveFactor) = $.interestRateModule.calculateInterestRate(ilkIndex, totalDebt, totalEthSupply);
        borrowRate += RAY;
    }

    function calculateRewardAndDebtDistribution(uint8 ilkIndex)
        external
        view
        returns (
            uint256 supplyFactorIncrease,
            uint256 treasuryMintAmount,
            uint104 newRateIncrease,
            uint256 newDebtIncrease,
            uint48 newTimestampIncrease
        )
    {
        return _calculateRewardAndDebtDistribution(ilkIndex, totalSupply());
    }

    function implementation() external view returns (address) {
        return ADDRESS_THIS;
    }

    // --- Auth ---

    function addOperator(address operator) external {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.isOperator[_msgSender()][operator] = 1;

        emit AddOperator(_msgSender(), operator);
    }

    function removeOperator(address operator) external {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.isOperator[_msgSender()][operator] = 0;

        emit RemoveOperator(_msgSender(), operator);
    }

    // --- Math ---

    function _add(uint256 x, int256 y) internal pure returns (uint256 z) {
        // Overflow desirable
        unchecked {
            z = x + uint256(y);
        }
        if (y < 0 && z > x) revert ArithmeticError();
        if (y > 0 && z < x) revert ArithmeticError();
    }

    function _sub(uint256 x, int256 y) internal pure returns (uint256 z) {
        // Underflow desirable
        unchecked {
            z = x - uint256(y);
        }
        if (y > 0 && z > x) revert ArithmeticError();
        if (y < 0 && z < x) revert ArithmeticError();
    }

    /**
     * @dev x and the returned value are to be interpreted as fixed-point
     * integers with scaling factor b. For example, if b == 100, this specifies
     * two decimal digits of precision and the normal decimal value 2.1 would be
     * represented as 210; rpow(210, 2, 100) returns 441 (the two-decimal digit
     * fixed-point representation of 2.1^2 = 4.41) (From MCD docs)
     * @param x base
     * @param n exponent
     * @param b scaling factor
     */
    function _rpow(uint256 x, uint256 n, uint256 b) internal pure returns (uint256 z) {
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := b }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := b }
                default { z := x }
                let half := div(b, 2) // for rounding.
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, b)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, b)
                    }
                }
            }
        }
    }

    // --- Boolean ---

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly {
            z := or(x, y)
        }
    }

    function both(bool x, bool y) internal pure returns (bool z) {
        assembly {
            z := and(x, y)
        }
    }
}
