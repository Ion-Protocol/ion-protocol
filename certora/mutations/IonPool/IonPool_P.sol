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

    event Supply(
        address indexed user, address indexed underlyingFrom, uint256 amount, uint256 supplyFactor, uint256 newDebt
    );

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
        uint104 totalNormalizedDebt; // Total Normalised Debt     [WAD]
        uint104 rate; // Accumulated Rates         [RAY]
        uint48 lastRateUpdate; // block.timestamp of last update; overflows in 800_000 years
        SpotOracle spot; // Oracle that provides price with safety margin
        uint256 debtCeiling; // Debt Ceiling              [RAD]
        uint256 dust; // Vault Debt Floor            [RAD]
    }

    struct Vault {
        uint256 collateral; // Locked Collateral  [WAD]
        uint256 normalizedDebt; // Normalised Debt    [WAD]
    }

    struct IonPoolStorage {
        Ilk[] ilks;
        // remove() should never be called, it will mess up the ordering
        EnumerableSet.AddressSet ilkAddresses;
        mapping(uint256 ilkIndex => mapping(address user => Vault)) vaults;
        mapping(uint256 ilkIndex => mapping(address user => uint256)) gem; // [WAD]
        mapping(address => uint256) unbackedDebt; // [RAD]
        mapping(address => mapping(address => uint256)) isOperator;
        uint256 debt; // Total Debt [RAD]
        uint256 weth; // liquidity in pool [WAD]
        uint256 wethSupplyCap; // [WAD]
        uint256 totalUnbackedDebt; // Total Unbacked Dai  [RAD]
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
        RewardModule._initialize(_underlying, _treasury, decimals_, name_, symbol_);

        _grantRole(ION, initialDefaultAdmin);

        IonPoolStorage storage $ = _getIonPoolStorage();

        $.interestRateModule = _interestRateModule;
        $.whitelist = _whitelist;

        emit InterestRateModuleUpdated(address(_interestRateModule));
        emit WhitelistUpdated(address(_whitelist));
    }

    // --- Administration ---

    /**
     * @notice Initializes a market with a new collateral type.
     * @dev This function and the entire protocol as a whole operates under the
     * assumption that there will never be more than 256 collaterals.
     * @param ilkAddress address of the ERC-20 collateral.
     */
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

    /**
     * @dev Updates the spot oracle for a given collateral.
     * @param ilkIndex index of the collateral.
     * @param newSpot address of the new spot oracle.
     */
    function updateIlkSpot(uint8 ilkIndex, SpotOracle newSpot) external onlyRole(ION) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.ilks[ilkIndex].spot = newSpot;

        emit IlkSpotUpdated(address(newSpot));
    }

    /**
     * @notice A market can be sunset by setting the debt ceiling to 0. It would
     * still be possible to repay debt but creating new debt would not be
     * possible.
     * @dev Updates the debt ceiling for a given collateral.
     * @param ilkIndex index of the collateral.
     * @param newCeiling new debt ceiling.
     */
    function updateIlkDebtCeiling(uint8 ilkIndex, uint256 newCeiling) external onlyRole(ION) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.ilks[ilkIndex].debtCeiling = newCeiling;

        emit IlkDebtCeilingUpdated(newCeiling);
    }

    /**
     * @notice When increasing the `dust`, it is possible that some vaults will
     * be dusty after the update. However, changes to the vault position from
     * there will require that the vault be non-dusty (either by repaying all
     * debt or increasing debt beyond the `dust`).
     * @dev Updates the dust amount for a given collateral.
     * @param ilkIndex index of the collateral.
     * @param newDust new dust
     */
    function updateIlkDust(uint8 ilkIndex, uint256 newDust) external onlyRole(ION) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.ilks[ilkIndex].dust = newDust;

        emit IlkDustUpdated(newDust);
    }

    /**
     * @notice Reducing the supply cap will not affect existing deposits.
     * However, if it is below the `totalSupply`, then no new deposits will be
     * allowed until the `totalSupply` is below the new `supplyCap`.
     * @dev Updates the supply cap.
     * @param newSupplyCap new supply cap.
     */
    function updateSupplyCap(uint256 newSupplyCap) external onlyRole(ION) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.wethSupplyCap = newSupplyCap;

        emit SupplyCapUpdated(newSupplyCap);
    }

    /**
     * @dev Updates the interest rate module. There is a check to ensure that
     * `collateralCount()` on the new interest rate module match the current
     * number of collaterals in the pool.
     * @param _interestRateModule new interest rate module.
     */
    function updateInterestRateModule(InterestRate _interestRateModule) external onlyRole(ION) {
        if (address(_interestRateModule) == address(0)) revert InvalidInterestRateModule(_interestRateModule);

        IonPoolStorage storage $ = _getIonPoolStorage();

        // Sanity check
        if (_interestRateModule.COLLATERAL_COUNT() != $.ilks.length) {
            revert InvalidInterestRateModule(_interestRateModule);
        }
        $.interestRateModule = _interestRateModule;

        emit InterestRateModuleUpdated(address(_interestRateModule));
    }

    /**
     * @dev Updates the whitelist.
     * @param _whitelist new whitelist address.
     */
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

    /**
     * @dev Updates accumulators for all `ilk`s based on current interest rates.
     * @return newTotalDebt the new total debt after interest accrual
     */
    function accrueInterest() external whenNotPaused(Pauses.SAFE) returns (uint256 newTotalDebt) {
        return _accrueInterest();
    }

    function _accrueInterest() internal returns (uint256 newTotalDebt) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        // Safe actions should really only be paused in conjunction with unsafe
        // actions. However, if for some reason only safe actions were paused,
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
            $.debt += newDebtIncrease;

            _setSupplyFactor(supplyFactor() + supplyFactorIncrease);
            _mintToTreasury(treasuryMintAmount);
        }
    }

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

        // Calculates borrowRate ^ (time) and returns the result with RAY precision
        uint256 borrowRateExpT = _rpow(borrowRate + RAY, block.timestamp - ilk.lastRateUpdate, RAY);

        // Unsafe cast OK
        timestampIncrease = uint48(block.timestamp) - ilk.lastRateUpdate;

        // Debt distribution
        // This form of rate accrual is much safer than distributing the new
        // debt increase to the total debt since low debt amounts won't cause
        // rounding errors to sky rocket the rate. This form of accrual is still
        // subject to rate inflation, however, it would only be from an
        // extremely high borrow rate rather than being a function of the
        // current total debt in the system. This is very relevant for
        // sunsetting markets, where the goal will be to reduce the total debt
        // to 0.
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

    /**
     * @dev Allows lenders to redeem their interest-bearing position for the
     * underlying asset. It is possible that dust amounts more of the position
     * are burned than the underlying received due to rounding.
     * @param receiverOfUnderlying the address to which the redeemed underlying
     * asset should be sent to.
     * @param amount of underlying to reedeem for.
     */
    function withdraw(address receiverOfUnderlying, uint256 amount) external whenNotPaused(Pauses.UNSAFE) {
        uint256 newTotalDebt = _accrueInterest();
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.weth -= amount;

        uint256 _supplyFactor =
            _burn({ user: _msgSender(), receiverOfUnderlying: receiverOfUnderlying, amount: amount });

        emit Withdraw(_msgSender(), receiverOfUnderlying, amount, _supplyFactor, newTotalDebt);
    }

    /**
     * @dev Allows lenders to deposit their underlying asset into the pool and
     * earn interest on it.
     * @param user the address to receive credit for the position.
     * @param amount of underlying asset to use to create the position.
     * @param proof merkle proof that the user is whitelisted.
     */
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

        $.weth += amount;

        uint256 _supplyFactor = _mint({ user: user, senderOfUnderlying: _msgSender(), amount: amount });

        uint256 _supplyCap = $.wethSupplyCap;
        if (totalSupply() > _supplyCap) revert DepositSurpassesSupplyCap(amount, _supplyCap);

        emit Supply(user, _msgSender(), amount, _supplyFactor, newTotalDebt);
    }

    // --- Borrower Operations ---

    /**
     * @dev Allows a borrower to create debt in a position.
     * @param ilkIndex index of the collateral.
     * @param user to create the position for.
     * @param recipient to receive the borrowed funds
     * @param amountOfNormalizedDebt to create.
     * @param proof merkle proof that the user is whitelist.
     */
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

    /**
     * @dev Allows a borrower to repay debt in a position.
     * @param ilkIndex index of the collateral.
     * @param user to repay the debt for.
     * @param payer to source the funds from.
     * @param amountOfNormalizedDebt to repay.
     */
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
     * @param ilkIndex index of the collateral.
     * @param user to withdraw the collateral for.
     * @param recipient to receive the collateral.
     * @param amount to withdraw.
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
     * @param ilkIndex index of the collateral.
     * @param user to deposit the collateral for.
     * @param depositor to deposit the collateral from.
     * @param amount to deposit.
     * @param proof merkle proof that the user is whitelisted.
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

        Vault memory _vault = $.vaults[ilkIndex][u];
        _vault.collateral = _add(_vault.collateral, changeInCollateral);
        _vault.normalizedDebt = _add(_vault.normalizedDebt, changeInNormalizedDebt);

        uint104 _totalNormalizedDebt = _add($.ilks[ilkIndex].totalNormalizedDebt, changeInNormalizedDebt).toUint104();

        // Prevent stack too deep
        {
            uint256 newTotalDebtInVault = ilkRate * _vault.normalizedDebt;
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
                    newTotalDebtInVault > _vault.collateral * ilkSpot
                )
            ) revert UnsafePositionChange(newTotalDebtInVault, _vault.collateral, ilkSpot);

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
            if (both(_vault.normalizedDebt != 0, newTotalDebtInVault < $.ilks[ilkIndex].dust)) {
                revert VaultCannotBeDusty(newTotalDebtInVault, $.ilks[ilkIndex].dust);
            }
        }

        int256 changeInDebt = ilkRate.toInt256() * changeInNormalizedDebt;

        // mutation `v` -> `w`
        $.gem[ilkIndex][w] = _sub($.gem[ilkIndex][v], changeInCollateral);
        $.vaults[ilkIndex][u] = _vault;
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
     * @param amount amount to transfer [RAD]
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
     * @param ilkIndex index of the collateral.
     * @param u user to confiscate the vault from.
     * @param v address to either credit `gem` to or deduct `gem` from
     * @param changeInCollateral collateral to add or remove from the vault
     * @param changeInNormalizedDebt debt to add or remove from the vault
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
        _accrueInterestForIlk(ilkIndex); 

        IonPoolStorage storage $ = _getIonPoolStorage();

        Vault storage _vault = $.vaults[ilkIndex][u];
        Ilk storage ilk = $.ilks[ilkIndex];
        uint104 ilkRate = ilk.rate;

        _vault.collateral = _add(_vault.collateral, changeInCollateral);
        _vault.normalizedDebt = _add(_vault.normalizedDebt, changeInNormalizedDebt);
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
        onlyRole(GEM_JOIN_ROLE)
    {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.gem[ilkIndex][usr] = _add($.gem[ilkIndex][usr], wad);

        emit MintAndBurnGem(ilkIndex, usr, wad);
    }

    /**
     * @dev Transfer gem across the internal accounting of the pool
     * @param ilkIndex index of the collateral
     * @param src source of the gem
     * @param dst destination of the gem
     * @param wad amount of gem
     */
    function transferGem(uint8 ilkIndex, address src, address dst, uint256 wad) external whenNotPaused(Pauses.UNSAFE) {
        if (!isAllowed(src, _msgSender())) revert GemTransferWithoutConsent(ilkIndex, src, _msgSender());

        IonPoolStorage storage $ = _getIonPoolStorage();

        $.gem[ilkIndex][src] -= wad;
        $.gem[ilkIndex][dst] += wad;
        emit TransferGem(ilkIndex, src, dst, wad);
    }

    // --- Getters ---

    /**
     * @return The total amount of collateral in the pool.
     */
    function ilkCount() public view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks.length;
    }

    /**
     * @return The index of the collateral with `ilkAddress`.
     */
    function getIlkIndex(address ilkAddress) public view returns (uint8) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        bytes32 addressInBytes32 = bytes32(uint256(uint160(ilkAddress)));

        // Since there should never be more than 256 collaterals, an unsafe cast
        // should be fine
        return uint8($.ilkAddresses._inner._positions[addressInBytes32] - 1);
    }

    /**
     * @return The address of the collateral at index `ilkIndex`.
     */
    function getIlkAddress(uint256 ilkIndex) public view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilkAddresses.at(ilkIndex);
    }

    /**
     * @return Whether or not an address is a supported collateral.
     */
    function addressContains(address ilk) public view returns (bool) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilkAddresses.contains(ilk);
    }

    /**
     * @return The total amount of addresses.
     */
    function addressesLength() public view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilkAddresses.length();
    }

    /**
     * @return The total amount of normalized debt for collateral with index
     * `ilkIndex`.
     */
    function totalNormalizedDebt(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].totalNormalizedDebt;
    }

    /**
     * @return The rate (debt accumulator) for collateral with index `ilkIndex`.
     */
    function rate(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].rate;
    }

    /**
     * @return The timestamp of the last rate update for collateral with index
     * `ilkIndex`.
     */
    function lastRateUpdate(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].lastRateUpdate;
    }

    /**
     * @return The spot oracle for collateral with index `ilkIndex`.
     */
    function spot(uint8 ilkIndex) external view returns (SpotOracle) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].spot;
    }

    /**
     * @return debt ceiling for collateral with index `ilkIndex`.
     */
    function debtCeiling(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].debtCeiling;
    }

    /**
     * @return dust amount for collateral with index `ilkIndex`.
     */
    function dust(uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.ilks[ilkIndex].dust;
    }

    /**
     * @return The amount of collateral `user` has for collateral with index `ilkIndex`.
     */
    function collateral(uint8 ilkIndex, address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.vaults[ilkIndex][user].collateral;
    }

    /**
     * @return The amount of normalized debt `user` has for collateral with index `ilkIndex`.
     */
    function normalizedDebt(uint8 ilkIndex, address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.vaults[ilkIndex][user].normalizedDebt;
    }

    /**
     * @return All data within vault for `user` with index `ilkIndex`.
     */
    function vault(uint8 ilkIndex, address user) external view returns (uint256, uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return ($.vaults[ilkIndex][user].collateral, $.vaults[ilkIndex][user].normalizedDebt);
    }

    /**
     * @return Amount of `gem` that `user` has for collateral with index `ilkIndex`.
     */
    function gem(uint8 ilkIndex, address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.gem[ilkIndex][user];
    }

    /**
     * @return The amount of unbacked debt `user` has.
     */
    function unbackedDebt(address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.unbackedDebt[user];
    }

    /**
     * @return Whether or not `operator` is an `operator` on `user`'s positions.
     */
    function isOperator(address user, address operator) external view returns (bool) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.isOperator[user][operator] == 1;
    }

    /**
     * @return Whether or not `operator` has permission to make unsafe changes
     * to `user`'s positions.
     */
    function isAllowed(address user, address operator) public view returns (bool) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        return either(user == operator, $.isOperator[user][operator] == 1);
    }

    /**
     * @dev This includes unbacked debt.
     * @return The total amount of debt.
     */
    function debt() external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.debt;
    }

    /**
     * @return The total amount of unbacked debt.
     */
    function totalUnbackedDebt() external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.totalUnbackedDebt;
    }

    /**
     * @return The address of interest rate module.
     */
    function interestRateModule() external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return address($.interestRateModule);
    }

    /**
     * @return The address of the whitelist.
     */
    function whitelist() external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return address($.whitelist);
    }

    /**
     * @return The total amount of ETH liquidity in the pool.
     */
    function weth() external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.weth;
    }

    /**
     * @dev Gets the current borrow rate for borrowing against a given collateral.
     */
    function getCurrentBorrowRate(uint8 ilkIndex) public view returns (uint256 borrowRate, uint256 reserveFactor) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 totalEthSupply = totalSupply();
        uint256 _totalNormalizedDebt = $.ilks[ilkIndex].totalNormalizedDebt;
        uint256 _rate = $.ilks[ilkIndex].rate;

        uint256 totalDebt = _totalNormalizedDebt * _rate; // [WAD] * [RAY] / [WAD] = [RAY]

        (borrowRate, reserveFactor) = $.interestRateModule.calculateInterestRate(ilkIndex, totalDebt, totalEthSupply);
        borrowRate += RAY;
    }

    /**
     * @dev Calculates the increase in debt and supply factors for a given
     * `ilkIndex` should it's interest be accrued.
     *
     */
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

    /**
     * @dev Address of the implementation. This is stored immutably on the
     * implementation so that it can be read by the proxy.
     */
    function implementation() external view returns (address) {
        return ADDRESS_THIS;
    }

    // --- Auth ---

    /**
     * @dev Allows an `operator` to make unsafe changes to `_msgSender()`s
     * positions.
     */
    function addOperator(address operator) external {
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.isOperator[_msgSender()][operator] = 1;

        emit AddOperator(_msgSender(), operator);
    }

    /**
     * @dev Disallows an `operator` to make unsafe changes to `_msgSender()`s
     * positions.
     */
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
