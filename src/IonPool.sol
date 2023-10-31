// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { RewardModule } from "./reward/RewardModule.sol";
import { AccessControlDefaultAdminRulesUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { InterestRate } from "./InterestRate.sol";
import { RoundedMath, RAY } from "./libraries/math/RoundedMath.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IonPausableUpgradeable } from "./admin/IonPausableUpgradeable.sol";
import { Whitelist } from "src/Whitelist.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { console2 } from "forge-std/console2.sol";
import { SpotOracle } from "src/oracles/spot/SpotOracle.sol";

contract IonPool is IonPausableUpgradeable, AccessControlDefaultAdminRulesUpgradeable, RewardModule {
    using SafeERC20 for IERC20;
    using SafeCast for *;
    using RoundedMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // --- Errors ---
    error CeilingExceeded(uint256 newDebt, uint256 debtCeiling);
    error UnsafePositionChange(uint256 newTotalDebtInVault, uint256 collateral, uint256 spot);
    error UnsafePositionChangeWithoutConsent(address user, address unconsentedOperator);
    error GemTransferWithoutConsent(address user, address unconsentedOperator);
    error UseOfCollateralWithoutConsent(address user, address unconsentedOperator);
    error TakingWethWithoutConsent(address user, address unconsentedOperator);
    error VaultCannotBeDusty(uint256 amountLeft, uint256 dust);
    error ArithmeticError();
    error SpotUpdaterNotAuthorized();
    error IlkAlreadyAdded(address ilkAddress);
    error IlkNotInitialized(uint256 ilkIndex);
    error DepositSurpassesSupplyCap(uint256 depositAmount, uint256 supplyCap);

    error InvalidIlkAddress();
    error InvalidAccountingModule();
    error InvalidInterestRateModule();

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

    event Borrow(
        uint8 indexed ilkIndex,
        address indexed user,
        address indexed recipient,
        uint256 amountOfNormalizedDebt,
        uint256 ilkRate
    );
    event Repay(
        uint8 indexed ilkIndex,
        address indexed user,
        address indexed payer,
        uint256 amountOfNormalizedDebt,
        uint256 ilkRate
    );

    event DepositCollateral(uint8 indexed ilkIndex, address indexed user, address indexed depositor, uint256 amount);
    event WithdrawCollateral(uint8 indexed ilkIndex, address indexed user, address indexed recipient, uint256 amount);

    event RepayBadDebt(address indexed user, address indexed payer, uint256 rad);
    event ConfiscateVault(
        uint8 indexed ilkIndex,
        address indexed u,
        address v,
        address indexed w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    );

    bytes32 public constant ION = keccak256("ION");
    bytes32 public constant SPOT_ROLE = keccak256("SPOT_ROLE");
    bytes32 public constant GEM_JOIN_ROLE = keccak256("GEM_JOIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    address private immutable addressThis = address(this);

    // --- Modifiers ---
    modifier onlyWhitelistedBorrowers(bytes32[] memory proof) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        $.whitelist.isWhitelistedBorrower(proof, _msgSender());
        _;
    }

    modifier onlyWhitelistedLenders(bytes32[] memory proof) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        $.whitelist.isWhitelistedLender(proof, _msgSender());
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
        uint256 weth; // liquidity in pool [wad]
        uint256 wethSupplyCap; // [wad]
        uint256 debt; // Total Dai Issued    [rad]
        uint256 totalUnbackedDebt; // Total Unbacked Dai  [rad]
        InterestRate interestRateModule;
        Whitelist whitelist;
    }

    // keccak256(abi.encode(uint256(keccak256("ion.storage.IonPool")) - 1)) & ~bytes32(uint256(0xff))
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
        ilk.lastRateUpdate = block.timestamp.toUint48();

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
        if (address(_interestRateModule) == address(0)) revert InvalidInterestRateModule();

        IonPoolStorage storage $ = _getIonPoolStorage();

        // Sanity check
        if (_interestRateModule.collateralCount() != $.ilks.length) revert InvalidInterestRateModule();
        $.interestRateModule = _interestRateModule;

        emit InterestRateModuleUpdated(address(_interestRateModule));
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
            $.ilks[i].lastRateUpdate = block.timestamp.toUint48();

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }
    }

    // --- Interest Calculations ---

    function accrueInterest() external whenNotPaused(Pauses.SAFE) {
        _accrueInterest();
    }

    function _accrueInterest() internal {
        // Safe actions should really only be paused in conjunction with unsafe
        // actions. However, if for some reason only safe actions were unpaused,
        // it would still be possible to accrue interest by withdrawing and/or
        // borrowing... so we prevent this outcome; but without reverting the tx
        // altogether.
        if (paused(Pauses.SAFE)) return;
        uint256 totalEthSupply = totalSupply();

        uint256 totalSupplyFactorIncrease;
        uint256 totalTreasuryMintAmount;

        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 ilksLength = $.ilks.length;
        for (uint8 i = 0; i < ilksLength;) {
            (uint256 supplyFactorIncrease, uint256 treasuryMintAmount, uint104 newRateIncrease, uint48 newTimestamp) =
                _calculateRewardAndDebtDistribution(i, totalEthSupply);

            if (newTimestamp > 0) {
                Ilk storage ilk = $.ilks[i];
                ilk.rate += newRateIncrease;
                ilk.lastRateUpdate = newTimestamp;

                totalSupplyFactorIncrease += supplyFactorIncrease;
                totalTreasuryMintAmount += treasuryMintAmount;
            }

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }

        _setSupplyFactor(supplyFactor() + totalSupplyFactorIncrease);
        _mintToTreasury(totalTreasuryMintAmount);
    }

    function _accrueInterestForIlk(uint8 ilkIndex) internal {
        (uint256 supplyFactorIncrease, uint256 treasuryMintAmount, uint104 newRateIncrease, uint48 newTimestamp) =
            _calculateRewardAndDebtDistribution(ilkIndex, totalSupply());

        IonPoolStorage storage $ = _getIonPoolStorage();

        if (newTimestamp > 0) {
            Ilk storage ilk = $.ilks[ilkIndex];
            ilk.rate += newRateIncrease;
            ilk.lastRateUpdate = newTimestamp;

            _setSupplyFactor(supplyFactor() + supplyFactorIncrease);
            _mintToTreasury(treasuryMintAmount);
        }
    }

    function calculateRewardAndDebtDistribution(
        uint8 ilkIndex,
        uint256 totalEthSupply
    )
        external
        view
        returns (uint256 supplyFactorIncrease, uint256 treasuryMintAmount, uint104 newRateIncrease, uint48 newTimestamp)
    {
        return _calculateRewardAndDebtDistribution(ilkIndex, totalEthSupply);
    }

    function _calculateRewardAndDebtDistribution(
        uint8 ilkIndex,
        uint256 totalEthSupply
    )
        internal
        view
        returns (uint256 supplyFactorIncrease, uint256 treasuryMintAmount, uint104 newRateIncrease, uint48 newTimestamp)
    {
        IonPoolStorage storage $ = _getIonPoolStorage();
        Ilk storage ilk = $.ilks[ilkIndex];

        uint256 _totalNormalizedDebt = ilk.totalNormalizedDebt;
        if (_totalNormalizedDebt == 0) return (0, 0, 0, 0);
        uint256 _rate = ilk.rate;

        uint256 totalDebt = _totalNormalizedDebt.wadMulDown(_rate); // [WAD] * [RAY] / [WAD] = [RAY]

        // TODO: Make this borrow rate less than one, and then add one in this contract. This way, the core guarantees
        // that borrow rate > 1
        (uint256 borrowRate, uint256 reserveFactor) =
            $.interestRateModule.calculateInterestRate(ilkIndex, totalDebt, totalEthSupply);

        uint256 borrowRateExpT = _rpow(borrowRate, block.timestamp - ilk.lastRateUpdate, RAY);

        newTimestamp = block.timestamp.toUint48();

        uint256 newDebtCreated = totalDebt.rayMulDown(borrowRateExpT - RAY); // Round down in protocol's favor.
        uint256 newDebtCreatedUp = totalDebt.rayMulUp(borrowRateExpT - RAY); // Round down in protocol's favor.

        // Debt distribution
        newRateIncrease = newDebtCreatedUp.rayDivUp(_totalNormalizedDebt).toUint104();

        // Income distribution
        uint256 _normalizedTotalSupply = normalizedTotalSupply();

        // If there is no supply, then nothing is being lent out.
        supplyFactorIncrease = _normalizedTotalSupply == 0
            ? 0
            : newDebtCreated.rayMulDown(RAY - reserveFactor).rayDivDown(_normalizedTotalSupply);

        treasuryMintAmount = newDebtCreated.rayMulDown(reserveFactor);
    }

    // --- Lender Operations ---
    function withdraw(address user, uint256 amount) external whenNotPaused(Pauses.UNSAFE) {
        _accrueInterest();
        IonPoolStorage storage $ = _getIonPoolStorage();

        $.weth -= amount;
        
        _burn(_msgSender(), user, amount);
    }

    // TODO: Supply caps
    function supply(
        address user,
        uint256 amount,
        bytes32[] calldata proof
    )
        external
        whenNotPaused(Pauses.SAFE)
        onlyWhitelistedLenders(proof)
    {
        _accrueInterest();
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 _supplyCap = $.wethSupplyCap;
        if (($.weth += amount) > _supplyCap) revert DepositSurpassesSupplyCap(amount, _supplyCap);

        _mint(user, amount);
    }

    // --- CDP Manipulation ---

    function borrow(
        uint8 ilkIndex,
        address user,
        address recipient,
        uint256 amountOfNormalizedDebt,
        bytes32[] calldata proof
    )
        external
        whenNotPaused(Pauses.UNSAFE)
        onlyWhitelistedBorrowers(proof)
    {
        _accrueInterestForIlk(ilkIndex);
        uint104 ilkRate = _modifyPosition(ilkIndex, user, address(0), recipient, 0, amountOfNormalizedDebt.toInt256());

        emit Borrow(ilkIndex, user, recipient, amountOfNormalizedDebt, ilkRate);
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
        uint104 ilkRate = _modifyPosition(ilkIndex, user, address(0), payer, 0, -(amountOfNormalizedDebt.toInt256()));

        emit Repay(ilkIndex, user, payer, amountOfNormalizedDebt, ilkRate);
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
        onlyWhitelistedBorrowers(proof)
    {
        _modifyPosition(ilkIndex, user, depositor, address(0), amount.toInt256(), 0);

        emit DepositCollateral(ilkIndex, user, depositor, amount);
    }

    function _modifyPosition(
        uint8 ilkIndex,
        address u,
        address v,
        address w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    )
        internal
        returns (uint104 ilkRate)
    {
        IonPoolStorage storage $ = _getIonPoolStorage();

        ilkRate = $.ilks[ilkIndex].rate;
        // ilk has been initialised
        if (ilkRate == 0) revert IlkNotInitialized(ilkIndex);

        Vault memory vault = $.vaults[ilkIndex][u];
        vault.collateral = _add(vault.collateral, changeInCollateral);
        vault.normalizedDebt = _add(vault.normalizedDebt, changeInNormalizedDebt);

        uint104 _totalNormalizedDebt = _add($.ilks[ilkIndex].totalNormalizedDebt, changeInNormalizedDebt).toUint104();
        int256 changeInDebt = ilkRate.toInt256() * changeInNormalizedDebt;

        uint256 newTotalDebtInVault = ilkRate * vault.normalizedDebt;

        // Prevent stack too deep
        {
            // either debt has decreased, or debt ceilings are not exceeded
            uint256 newDebt = uint256(_totalNormalizedDebt) * uint256(ilkRate);
            if (
                both(
                    changeInNormalizedDebt > 0,
                    // prevent intermediary overflow
                    newDebt > $.ilks[ilkIndex].debtCeiling
                )
            ) revert CeilingExceeded(newDebt, $.ilks[ilkIndex].debtCeiling);
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
                revert UnsafePositionChangeWithoutConsent(u, _msgSender());
            }

            // collateral src consents
            if (both(changeInCollateral > 0, !isAllowed(v, _msgSender()))) {
                revert UseOfCollateralWithoutConsent(v, _msgSender());
            }
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

        $.gem[ilkIndex][v] = _sub($.gem[ilkIndex][v], changeInCollateral);
        $.vaults[ilkIndex][u] = vault;
        $.ilks[ilkIndex].totalNormalizedDebt = _totalNormalizedDebt;
        $.debt = _add($.debt, changeInDebt);

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
     * @param amount amount to transfer
     */
    function _transferWeth(address user, int256 amount) internal {
        if (amount == 0) return;
        IonPoolStorage storage $ = _getIonPoolStorage();

        if (amount < 0) {
            // TODO: Round up using mulmod
            uint256 amountWad = uint256(-amount) / RAY;
            amountWad = amountWad * RAY < uint256(-amount) ? amountWad + 1 : amountWad;
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
        uint128 ilkRate = ilk.rate;

        vault.collateral = _add(vault.collateral, changeInCollateral);
        vault.normalizedDebt = _add(vault.normalizedDebt, changeInNormalizedDebt);
        ilk.totalNormalizedDebt = _add(uint256(ilk.totalNormalizedDebt), changeInNormalizedDebt).toUint104();

        // Unsafe cast OK since we know that ilkRate is less than 2^128
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
        if (!isAllowed(src, _msgSender())) revert GemTransferWithoutConsent(src, _msgSender());

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

    function weth() external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        return $.weth;
    }

    function getCurrentBorrowRate(uint8 ilkIndex) public view returns (uint256 borrowRate, uint256 reserveFactor) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 totalEthSupply = totalSupply();
        uint256 _totalNormalizedDebt = $.ilks[ilkIndex].totalNormalizedDebt;
        uint256 _rate = $.ilks[ilkIndex].rate;

        uint256 totalDebt = _totalNormalizedDebt.wadMulDown(_rate); // [WAD] * [RAY] / [WAD] = [RAY]

        (borrowRate, reserveFactor) = $.interestRateModule.calculateInterestRate(ilkIndex, totalDebt, totalEthSupply);
    }

    function calculateRewardAndDebtDistribution(uint8 ilkIndex)
        external
        view
        returns (uint256 supplyFactorIncrease, uint256 treasuryMintAmount, uint104 newRate, uint48 newTimestamp)
    {
        return _calculateRewardAndDebtDistribution(ilkIndex, totalSupply());
    }

    function implementation() external view returns (address) {
        return addressThis;
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
