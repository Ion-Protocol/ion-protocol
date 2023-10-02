// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IIonPool } from "./interfaces/IIonPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { RewardToken } from "./token/RewardToken.sol";
import { AccessControlDefaultAdminRules as AccessControl } from
    "@openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { InterestRate } from "./InterestRate.sol";
import { RoundedMath, RAY } from "./math/RoundedMath.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";

contract IonPool is Pausable, AccessControl, RewardToken {
    error CeilingExceeded();
    error UnsafePositionChange();
    error UnsafePositionChangeWithoutConsent();
    error UseOfCollateralWithoutConsent();
    error TakingWethWithoutConsent();
    error VaultCannotBeDusty();
    error InvalidInterestRateModule();
    error ArithmeticError();
    error SpotUpdaterNotAuthorized();
    error IlkAlreadyAdded();

    using SafeERC20 for IERC20;
    using SafeCast for *;
    using RoundedMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant ION = keccak256("ION");
    bytes32 public constant SPOT_ROLE = keccak256("SPOT_ROLE");
    bytes32 public constant GEM_JOIN_ROLE = keccak256("GEM_JOIN_ROLE");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    // --- Data ---
    struct Ilk {
        uint104 totalNormalizedDebt; // Total Normalised Debt     [wad]
        uint104 rate; // Accumulated Rates         [ray]
        uint48 lastRateUpdate; // block.timestamp of last update; overflows in 800_000 years
        uint256 spot; // Price with Safety Margin  [ray]
        uint256 debtCeiling; // Debt Ceiling              [rad]
        uint256 dust; // Vault Debt Floor            [rad]
    }

    struct Vault {
        uint256 collateral; // Locked Collateral  [wad]
        uint256 normalizedDebt; // Normalised Debt    [wad]
    }

    Ilk[] public ilks;
    // remove() should never be called, it will mess up the ordering
    EnumerableSet.AddressSet internal ilkAddresses;

    mapping(uint256 ilkIndex => mapping(address user => Vault)) public vaults;
    mapping(uint256 ilkIndex => mapping(address user => uint256)) public gem; // [wad]
    mapping(address => uint256) public weth; // [rad]
    mapping(address => uint256) public unbackedDebt; // [rad]

    mapping(address => mapping(address => uint256)) public can;

    uint256 public debt; // Total Dai Issued    [rad]
    uint256 public totalUnbackedDebt; // Total Unbacked Dai  [rad]
    uint256 public globalDebtCeiling; // Total Debt Ceiling  [rad]

    InterestRate public interestRateModule;

    constructor(
        address _underlying,
        address _treasury,
        uint8 decimals_,
        string memory name_,
        string memory symbol_,
        address initialDefaultAdmin,
        InterestRate _interestRateModule
    )
        RewardToken(_underlying, _treasury, decimals_, name_, symbol_)
        AccessControl(0, initialDefaultAdmin)
    {
        interestRateModule = _interestRateModule;
    }

    // --- Administration ---

    function init(address ilkAddress) external onlyRole(ION) {
        if (!ilkAddresses.add(ilkAddress)) revert IlkAlreadyAdded();

        uint256 ilkIndex = ilks.length;
        Ilk memory newIlk;
        ilks.push(newIlk);
        Ilk storage ilk = ilks[ilkIndex];

        ilk.rate = 10 ** 27;
        ilk.lastRateUpdate = block.timestamp.toUint48();
    }

    function updateGlobalDebtCeiling(uint256 newCeiling) external onlyRole(ION) whenNotPaused {
        globalDebtCeiling = newCeiling;
    }

    function updateIlkSpot(uint8 ilkIndex, uint256 newSpot) external whenNotPaused {
        if (!hasRole(SPOT_ROLE, _msgSender()) && !hasRole(ION, _msgSender())) revert SpotUpdaterNotAuthorized();
        ilks[ilkIndex].spot = newSpot;
    }

    function updateIlkDebtCeiling(uint8 ilkIndex, uint256 newCeiling) external onlyRole(ION) whenNotPaused {
        ilks[ilkIndex].debtCeiling = newCeiling;
    }

    function updateIlkDust(uint8 ilkIndex, uint256 newDust) external onlyRole(ION) whenNotPaused {
        ilks[ilkIndex].dust = newDust;
    }

    function updateIlkConfig(
        uint8 ilkIndex,
        uint256 newSpot,
        uint256 newDebtCeiling,
        uint256 newDust
    )
        external
        onlyRole(ION)
        whenNotPaused
    {
        Ilk storage ilk = ilks[ilkIndex];

        ilk.spot = newSpot;
        ilk.debtCeiling = newDebtCeiling;
        ilk.dust = newDust;
    }

    function setInterestRateModule(InterestRate _interestRateModule) external onlyRole(ION) {
        if (address(_interestRateModule) == address(0)) revert InvalidInterestRateModule();
        // Sanity check
        if (_interestRateModule.collateralCount() != ilks.length) revert InvalidInterestRateModule();
        interestRateModule = _interestRateModule;
    }

    function pause() external onlyRole(ION) {
        _pause();
    }

    function unpause() external onlyRole(ION) {
        _unpause();
    }

    // --- Interest Calculations ---

    function _accrueInterest() internal {
        uint256 totalEthSupply = totalSupply();

        uint256 totalSupplyFactorIncrease;
        uint256 totalTreasuryMintAmount;
        for (uint8 i = 0; i < ilks.length;) {
            (uint256 supplyFactorIncrease, uint256 treasuryMintAmount) = _calculateRewardDistribution(i, totalEthSupply);

            totalSupplyFactorIncrease += supplyFactorIncrease;
            totalTreasuryMintAmount += treasuryMintAmount;

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }

        supplyFactor += totalSupplyFactorIncrease;
        _mintToTreasury(totalTreasuryMintAmount);
    }

    function _accrueInterestForIlk(uint8 ilkIndex) internal {
        (uint256 supplyFactorIncrease, uint256 treasuryMintAmount) =
            _calculateRewardDistribution(ilkIndex, totalSupply());

        supplyFactor += supplyFactorIncrease;
        _mintToTreasury(treasuryMintAmount);
    }

    function _calculateRewardDistribution(
        uint8 ilkIndex,
        uint256 totalEthSupply
    )
        internal
        returns (uint256 supplyFactorIncrease, uint256 treasuryMintAmount)
    {
        uint256 _totalNormalizedDebt = ilks[ilkIndex].totalNormalizedDebt;
        uint256 _rate = ilks[ilkIndex].rate;

        uint256 totalDebt = _totalNormalizedDebt.roundedWadMul(_rate); // [WAD] * [RAY] / [WAD] = [RAY]

        (uint256 borrowRate, uint256 reserveFactor) =
            interestRateModule.calculateInterestRate(ilkIndex, totalDebt, totalEthSupply);

        uint256 borrowRateExpT = _rpow(borrowRate, block.timestamp - ilks[ilkIndex].lastRateUpdate, RAY);
        uint104 newRate = _rate.roundedRayMul(borrowRateExpT).toUint104();

        // Update borrow accumulator
        ilks[ilkIndex].rate = newRate;
        ilks[ilkIndex].lastRateUpdate = block.timestamp.toUint48();

        uint256 newDebtCreated = totalDebt.roundedRayMul(borrowRateExpT - RAY);

        // If there is no supply, then nothing is being lent out.
        supplyFactorIncrease = normalizedTotalSupply == 0
            ? 0
            : newDebtCreated.roundedRayMul(RAY - reserveFactor).roundedRayDiv(normalizedTotalSupply);

        treasuryMintAmount = newDebtCreated.roundedRayMul(reserveFactor);
    }

    // --- Lender Operations ---

    // TODO: Supply caps
    function supply(address user, uint256 amt) external whenNotPaused {
        _accrueInterest();
        _mint(user, amt);
    }

    function withdraw(address user, uint256 amt) external whenNotPaused {
        _accrueInterest();
        _burn(_msgSender(), user, amt);
    }

    // --- Borrower Operations ---

    /**
     * @param ilkIndex index of the collateral to borrow again
     * @param amt amount to borrow
     */
    function borrow(uint8 ilkIndex, uint256 amt) external {
        uint256 normalizedAmount = amt.roundedRayDiv(ilks[ilkIndex].rate); // [WAD] * [RAY] / [RAY] = [WAD]

        // Moves all gem into the vault ink
        modifyPosition(
            ilkIndex,
            _msgSender(),
            _msgSender(),
            _msgSender(),
            gem[ilkIndex][_msgSender()].toInt256(),
            normalizedAmount.toInt256()
        );

        exitBase(_msgSender(), amt);
    }

    function repay(uint8 ilkIndex, uint256 amt) external {
        uint256 normalizedAmount = amt.roundedRayDiv(ilks[ilkIndex].rate);

        joinBase(_msgSender(), amt);

        modifyPosition(ilkIndex, _msgSender(), _msgSender(), _msgSender(), 0, -normalizedAmount.toInt256());
    }

    /**
     * @dev converts internal weth to the erc20 WETH
     * @param amount of weth to exit in wad
     */
    function exitBase(address exitRecipient, uint256 amount) public whenNotPaused {
        uint256 amountRay = amount * RAY;
        weth[_msgSender()] -= amountRay;
        underlying.safeTransfer(exitRecipient, amount);
    }

    /**
     * @notice To be used by borrowers to re-enter their debt into the system so
     * that it can be paid off
     */
    function joinBase(address wethRecipient, uint256 amount) public whenNotPaused {
        uint256 amountRay = amount * RAY;
        weth[wethRecipient] += amountRay;
        underlying.safeTransferFrom(_msgSender(), address(this), amount);
    }

    // --- CDP Manipulation ---

    function modifyPosition(
        uint8 ilkIndex,
        address u,
        address v,
        address w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    )
        public
        whenNotPaused
    {
        _accrueInterestForIlk(ilkIndex);

        Vault memory vault = vaults[ilkIndex][u];
        Ilk memory ilk = ilks[ilkIndex];
        uint128 ilkRate = ilks[ilkIndex].rate;
        // ilk has been initialised
        require(ilkRate != 0, "Vat/ilk-not-init");

        vault.collateral = _add(vault.collateral, changeInCollateral);
        vault.normalizedDebt = _add(vault.normalizedDebt, changeInNormalizedDebt);
        ilk.totalNormalizedDebt = _add(uint256(ilk.totalNormalizedDebt), changeInNormalizedDebt).toUint104();

        int256 changeInDebt = ilkRate.toInt256() * changeInNormalizedDebt;
        uint256 newTotalDebtInVault = ilkRate * vault.normalizedDebt;
        debt = _add(debt, changeInDebt);

        // either debt has decreased, or debt ceilings are not exceeded
        if (
            both(
                changeInNormalizedDebt > 0,
                // prevent intermediary overflow
                either(uint256(ilk.totalNormalizedDebt) * uint256(ilkRate) > ilk.debtCeiling, debt > globalDebtCeiling)
            )
        ) revert CeilingExceeded();
        // vault is either less risky than before, or it is safe
        if (
            both(
                either(changeInNormalizedDebt > 0, changeInCollateral < 0),
                newTotalDebtInVault > vault.collateral * ilk.spot
            )
        ) revert UnsafePositionChange();

        // vault is either more safe, or the owner consents
        if (both(either(changeInNormalizedDebt > 0, changeInCollateral < 0), !wish(u, _msgSender()))) {
            revert UnsafePositionChangeWithoutConsent();
        }

        // collateral src consents
        if (both(changeInCollateral > 0, !wish(v, _msgSender()))) {
            revert UseOfCollateralWithoutConsent();
        }

        // debt dst consents
        if (both(changeInNormalizedDebt < 0, !wish(w, _msgSender()))) revert TakingWethWithoutConsent();

        // vault has no debt, or a non-dusty amount
        if (both(vault.normalizedDebt != 0, newTotalDebtInVault < ilk.dust)) revert VaultCannotBeDusty();

        gem[ilkIndex][v] = _sub(gem[ilkIndex][v], changeInCollateral);
        weth[w] = _add(weth[w], changeInDebt);

        vaults[ilkIndex][u] = vault;
        ilks[ilkIndex] = ilk;
    }

    // --- CDP Confiscation ---

    // TODO: Implement liquidations
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
        whenNotPaused
    {
        Vault storage vault = vaults[ilkIndex][u];
        Ilk storage ilk = ilks[ilkIndex];
        uint128 ilkRate = ilks[ilkIndex].rate;

        vault.collateral = _add(vault.collateral, changeInCollateral);
        vault.normalizedDebt = _add(vault.normalizedDebt, changeInNormalizedDebt);
        ilk.totalNormalizedDebt = _add(uint256(ilk.totalNormalizedDebt), changeInNormalizedDebt).toUint104();

        // Unsafe cast OK since we know that ilkRate is less than 2^128
        int256 changeInDebt = int256(uint256(ilkRate)) * changeInNormalizedDebt;

        gem[ilkIndex][v] = _sub(gem[ilkIndex][v], changeInCollateral);
        unbackedDebt[w] = _sub(unbackedDebt[w], changeInDebt);
        totalUnbackedDebt = _sub(totalUnbackedDebt, changeInDebt);
    }

    // --- Fungibility ---

    /**
     * @dev To be called by GemJoin contracts. After a user deposits collateral, credit the user with collateral
     * internally
     * @param ilkIndex collateral
     * @param usr user
     * @param wad amount to add or remove
     */
    function mintAndBurnGem(uint8 ilkIndex, address usr, int256 wad) external onlyRole(GEM_JOIN_ROLE) {
        gem[ilkIndex][usr] = _add(gem[ilkIndex][usr], wad);
    }

    function transferGem(uint8 ilkIndex, address src, address dst, uint256 wad) external whenNotPaused {
        require(wish(src, _msgSender()), "Vat/not-allowed");
        gem[ilkIndex][src] -= wad;
        gem[ilkIndex][dst] += wad;
    }

    function move(address src, address dst, uint256 rad) external whenNotPaused {
        require(wish(src, _msgSender()), "Vat/not-allowed");
        weth[src] -= rad;
        weth[dst] += rad;
    }

    // --- Settlement ---

    /**
     * @dev To be used by protocol to settle bad debt using reserves
     * @param rad amount of debt to be repaid (45 decimals)
     * @param usr the usr address that owns the bad debt
     * TODO: Allow a msg.sender to repay another address's unbackedDebt
     */
    function repayBadDebt(uint256 rad, address usr) external whenNotPaused {
        address u = _msgSender();
        unbackedDebt[usr] -= rad;
        weth[u] -= rad;
        totalUnbackedDebt -= rad;
        debt -= rad;
    }

    // --- Getters ---

    function ilkCount() public view returns (uint256) {
        return ilks.length;
    }

    function getIlkAddress(uint256 ilkIndex) public view returns (address) {
        return ilkAddresses.at(ilkIndex);
    }

    function addressContains(address ilk) public view returns (bool) {
        return ilkAddresses.contains(ilk);
    }

    function addressesLength() public view returns (uint256) {
        return ilkAddresses.length();
    }

    function totalNormalizedDebt(uint8 ilkIndex) external view returns (uint256) {
        return ilks[ilkIndex].totalNormalizedDebt;
    }

    function rate(uint8 ilkIndex) external view returns (uint256) {
        return ilks[ilkIndex].rate;
    }

    function spot(uint8 ilkIndex) external view returns (uint256) {
        return ilks[ilkIndex].spot;
    }

    function debtCeiling(uint8 ilkIndex) external view returns (uint256) {
        return ilks[ilkIndex].debtCeiling;
    }

    function dust(uint8 ilkIndex) external view returns (uint256) {
        return ilks[ilkIndex].dust;
    }

    function collateral(uint8 ilkIndex, address user) external view returns (uint256) {
        return vaults[ilkIndex][user].collateral;
    }

    function normalizedDebt(uint8 ilkIndex, address user) external view returns (uint256) {
        return vaults[ilkIndex][user].normalizedDebt;
    }

    function getCurrentBorrowRate(uint8 ilkIndex) public view returns (uint256 borrowRate, uint256 reserveFactor) {
        uint256 totalEthSupply = totalSupply();
        uint256 _totalNormalizedDebt = ilks[ilkIndex].totalNormalizedDebt;
        uint256 _rate = ilks[ilkIndex].rate;

        uint256 totalDebt = _totalNormalizedDebt.roundedWadMul(_rate); // [WAD] * [RAY] / [WAD] = [RAY]

        (borrowRate, reserveFactor) = interestRateModule.calculateInterestRate(ilkIndex, totalDebt, totalEthSupply);
    }

    // --- Auth ---

    function hope(address usr) external {
        can[_msgSender()][usr] = 1;
    }

    function nope(address usr) external {
        can[_msgSender()][usr] = 0;
    }

    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
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

    // TODO: Which role can call this?
    // function suck(address u, address v, uint256 rad) external onlyRole(ION) {
    //     sin[u] = _add(sin[u], rad);
    //     dai[v] = _add(dai[v], rad);
    //     vice = _add(vice, rad);
    //     debt = _add(debt, rad);
    // }

    // --- Rates ---
    // function fold(bytes32 i, address u, int256 rate) external onlyOwner whenNotPaused {
    //     Ilk storage ilk = ilks[i];
    //     ilkRate = _add(ilkRate, rate);
    //     int256 rad = _mul(ilk.totalNormalizedDebt, rate);
    //     dai[u] = _add(dai[u], rad);
    //     debt = _add(debt, rad);
    // }
}
