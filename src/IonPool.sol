// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IIonPool } from "./interfaces/IIonPool.sol";
import { Vat } from "./Vat.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { RewardToken } from "./token/RewardToken.sol";
import { AccessControlDefaultAdminRules as AccessControl } from
    "@openzeppelin/contracts/access/AccessControlDefaultAdminRules.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { InterestRate, InterestRateData } from "./InterestRate.sol";
import { RoundedMath, RAY } from "./math/RoundedMath.sol";

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

    using SafeERC20 for IERC20Metadata;
    using SafeCast for *;
    using RoundedMath for uint256;

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
    mapping(uint256 ilkIndex => mapping(address user => Vault)) public vaults;
    mapping(uint256 ilkIndex => mapping(address user => uint256)) public gem; // [wad]
    mapping(address => uint256) public weth; // [rad]
    mapping(address => uint256) public sin; // [rad]

    uint256 public debt; // Total Dai Issued    [rad]
    uint256 public vice; // Total Unbacked Dai  [rad]
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

    // TODO: Test which is more expensive, this implementation, or calling InterestRateModule in a loop
    function _accrueInterest() internal {
        uint256[] memory totalDebt = new uint256[](ilks.length);
        for (uint256 i = 0; i < ilks.length;) {
            totalDebt[i] = uint256(ilks[i].totalNormalizedDebt).roundedWadMul(ilks[i].rate);

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }

        InterestRateData[] memory interestRates = interestRateModule.calculateAllInterestRates(totalDebt, totalSupply());

        // Sanity check
        assert(interestRates.length == ilks.length);

        for (uint256 i = 0; i < interestRates.length;) {
            // TODO: Update supplyFactor once in end
            _updateBorrowAndSupplyRates(
                i, totalDebt[i], ilks[i].rate, interestRates[i].borrowRate, interestRates[i].reserveFactor
            );

            // forgefmt: disable-next-line
            unchecked { ++i; }
        }
    }

    function _accrueInterestForIlk(uint8 ilkIndex) internal {
        uint256 totalNormalizedDebt = ilks[ilkIndex].totalNormalizedDebt;
        uint256 rate = ilks[ilkIndex].rate;

        uint256 totalDebt = totalNormalizedDebt.roundedWadMul(rate); // [WAD] * [RAY] / [WAD] = [RAY]

        InterestRateData memory interestRateData =
            interestRateModule.calculateInterestRate(ilkIndex, totalDebt, totalSupply());

        _updateBorrowAndSupplyRates(
            ilkIndex, totalDebt, rate, interestRateData.borrowRate, interestRateData.reserveFactor
        );
    }

    function _updateBorrowAndSupplyRates(
        uint256 ilkIndex,
        uint256 totalDebt,
        uint256 rate,
        uint256 borrowRate,
        uint256 reserveFactor
    )
        internal
    {
        uint256 borrowRateExpT = _rpow(borrowRate, block.timestamp - ilks[ilkIndex].lastRateUpdate, RAY);
        uint256 newRate = rate.roundedWadMul(borrowRateExpT).toUint128();

        // Update borrow accumulator
        ilks[ilkIndex].rate = newRate.toUint104();
        ilks[ilkIndex].lastRateUpdate = block.timestamp.toUint48();

        uint256 newDebtCreated = totalDebt.roundedRayMul(borrowRateExpT - RAY);
        supplyFactor += newDebtCreated.roundedRayMul(RAY - reserveFactor).roundedRayDiv(normalizedTotalSupply);

        _mintToTreasury(newDebtCreated.roundedRayMul(reserveFactor));
    }

    // --- Lender Operations ---

    function supply(address user, uint256 amt) external whenNotPaused {
        _accrueInterest();
        _mint(user, amt);
    }

    function withdraw(address user, uint256 amt) external whenNotPaused {
        _accrueInterest();
        _burn(_msgSender(), user, amt);
    }

    // --- Borrower Operations ---

    // TODO: Discuss borrower action flows. Should borrows convert all gem to
    // vault collateral? Should repays convert all vault collateral to gem,
    // making it available for withdrawal? 

    /**
     * @param ilkIndex index of the collateral to borrow again
     * @param amt amount to borrow
     */
    function borrow(uint8 ilkIndex, uint256 amt) external whenNotPaused {
        _accrueInterestForIlk(ilkIndex);
        uint256 normalizedAmount = amt.roundedWadDiv(ilks[ilkIndex].rate);

        // Moves all gem into the vault ink
        _modifyPosition(ilkIndex, _msgSender(), _msgSender(), _msgSender(), gem[ilkIndex][_msgSender()].toInt256(), normalizedAmount.toInt256());
    }

    function repay(uint8 ilkIndex, uint256 amt) external whenNotPaused {
        _accrueInterestForIlk(ilkIndex);
        uint256 normalizedAmount = amt.roundedWadDiv(ilks[ilkIndex].rate);

        _modifyPosition(ilkIndex, _msgSender(), _msgSender(), _msgSender(), 0, -normalizedAmount.toInt256());
    }

    // --- Auth ---
    mapping(address => mapping(address => uint256)) public can;

    function hope(address usr) external {
        can[_msgSender()][usr] = 1;
    }

    function nope(address usr) external {
        can[msg.sender][usr] = 0;
    }

    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
    }

    // --- Math ---
    function _add(uint256 x, int256 y) internal pure returns (uint256 z) {
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

    // --- Administration ---
    function init(uint8 ilkIndex) external onlyRole(ION) {
        require(ilks[ilkIndex].rate == 0, "Vat/ilk-already-init");
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

    function updateIlk(uint8 ilkIndex, Ilk calldata newIlk) external onlyRole(ION) whenNotPaused {
        Ilk storage ilk = ilks[ilkIndex];

        ilk.spot = newIlk.spot;
        ilk.debtCeiling = newIlk.debtCeiling;
        ilk.dust = newIlk.dust;
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
        require(wish(src, msg.sender), "Vat/not-allowed");
        gem[ilkIndex][src] -= wad;
        gem[ilkIndex][dst] += wad;
    }

    function move(address src, address dst, uint256 rad) external whenNotPaused {
        require(wish(src, msg.sender), "Vat/not-allowed");
        weth[src] -= rad;
        weth[dst] += rad;
    }

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

    // --- CDP Manipulation ---

    function _modifyPosition(
        uint8 ilkIndex,
        address u,
        address v,
        address w,
        int256 changeInCollateral,
        int256 changeInNormalizedDebt
    )
        private
        whenNotPaused
    {
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
                either(ilk.totalNormalizedDebt * ilkRate > ilk.debtCeiling, debt > globalDebtCeiling)
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
        if (both(either(changeInNormalizedDebt > 0, changeInCollateral < 0), !wish(u, msg.sender))) {
            revert UnsafePositionChangeWithoutConsent();
        }

        // collateral src consents
        if (both(changeInCollateral > 0, !wish(v, msg.sender))) {
            revert UseOfCollateralWithoutConsent();
        }

        // debt dst consents
        if (both(changeInNormalizedDebt < 0, !wish(w, msg.sender))) revert TakingWethWithoutConsent();

        // vault has no debt, or a non-dusty amount
        if (both(vault.normalizedDebt != 0, newTotalDebtInVault < ilk.dust)) revert VaultCannotBeDusty();

        gem[ilkIndex][v] = _sub(gem[ilkIndex][v], changeInCollateral);
        weth[w] = _add(weth[w], changeInDebt);

        vaults[ilkIndex][u] = vault;
        ilks[ilkIndex] = ilk;
    }

    // --- CDP Confiscation ---

    // TODO: Implement liquidations
    function grab(
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
        sin[w] = _sub(sin[w], changeInDebt);
        vice = _sub(vice, changeInDebt);
    }

    // --- Settlement ---

    /**
     * @dev To be used by protocol to settle bad debt using reserves
     * @param rad amount of debt to be repaid (45 decimals)
     */
    function repayBadDebt(uint256 rad) external whenNotPaused {
        address u = msg.sender;
        sin[u] -= rad;
        weth[u] -= rad;
        vice -= rad;
        debt -= rad;
    }

    function ilkCount() public view returns (uint256) {
        return ilks.length;
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
