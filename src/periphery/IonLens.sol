// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IIonPool } from "../interfaces/IIonPool.sol";
import { IIonLens } from "../interfaces/IIonLens.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { StorageSlot } from "@openzeppelin/contracts/utils/StorageSlot.sol";

struct IlkSlot0 {
    uint104 totalNormalizedDebt; // Total Normalised Debt     [WAD]
    uint104 rate; // Accumulated Rates         [RAY]
    uint48 lastRateUpdate; // block.timestamp of last update; overflows in 800_000 years}
}

/**
 * @title Ion Lens
 * @author Molecular Labs
 * @notice Generalized lens contract for IonPools.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract IonLens is IIonLens {
    // --- Data ---
    struct Ilk {
        IlkSlot0 slot0;
        StorageSlot.AddressSlot spot; // Oracle that provides price with safety margin
        StorageSlot.Uint256Slot debtCeiling; // Debt Ceiling              [RAD]
        StorageSlot.Uint256Slot dust; // Vault Debt Floor            [RAD]
    }

    struct Vault {
        StorageSlot.Uint256Slot collateral; // Locked Collateral  [WAD]
        StorageSlot.Uint256Slot normalizedDebt; // Normalised Debt    [WAD]
    }

    /// @custom:storage-location erc7201:ion.storage.IonPool
    struct IonPoolStorage {
        Ilk[] ilks;
        // remove() should never be called, it will mess up the ordering
        EnumerableSet.AddressSet ilkAddresses;
        mapping(uint256 ilkIndex => mapping(address user => Vault)) vaults;
        mapping(uint256 ilkIndex => mapping(address user => StorageSlot.Uint256Slot)) gem; // [WAD]
        mapping(address unbackedDebtor => StorageSlot.Uint256Slot) unbackedDebt; // [RAD]
        mapping(address user => mapping(address operator => StorageSlot.Uint256Slot)) isOperator;
        StorageSlot.Uint256Slot debt; // Total Debt [RAD]
        StorageSlot.Uint256Slot liquidity; // liquidity in pool [WAD]
        StorageSlot.Uint256Slot supplyCap; // [WAD]
        StorageSlot.Uint256Slot totalUnbackedDebt; // Total Unbacked Underlying  [RAD]
        StorageSlot.AddressSlot interestRateModule;
        StorageSlot.AddressSlot whitelist;
    }

    // keccak256(abi.encode(uint256(keccak256("ion.storage.IonPool")) - 1)) & ~uint56(0xff))
    // solhint-disable-next-line
    bytes32 private constant IonPoolStorageLocation = 0xceba3d526b4d5afd91d1b752bf1fd37917c20a6daf576bcb41dd1c57c1f67e00;

    bytes4 private constant EXTSLOAD_SELECTOR = 0x1e2eaeaf;

    error SloadFailed();

    constructor() {
        IonPoolStorage storage $ = _getIonPoolStorage();

        // 4 collaterals should be enough. Must be initialized here to not
        // trigger an access-out-of-bounds error.
        $.ilks.push();
        $.ilks.push();
        $.ilks.push();
        $.ilks.push();
    }

    function _getIonPoolStorage() internal pure returns (IonPoolStorage storage $) {
        assembly {
            $.slot := IonPoolStorageLocation
        }
    }

    function _toUint256PointerMapping(mapping(bytes32 => uint256) storage inPtr)
        private
        pure
        returns (mapping(address => StorageSlot.Uint256Slot) storage outPtr)
    {
        assembly {
            outPtr.slot := inPtr.slot
        }
    }

    function queryPoolSlot(IIonPool pool, uint256 slot) public view returns (uint256 value) {
        assembly ("memory-safe") {
            mstore(0x00, EXTSLOAD_SELECTOR)
            mstore(0x04, slot)
            if iszero(staticcall(gas(), pool, 0x00, 0x24, 0x00, 0x20)) {
                mstore(0x00, 0x74d9f8d3) // SloadFailed()
                revert(0x1c, 0x04)
            }
            value := mload(0x00)
        }
    }

    /**
     * @return The total amount of collateral types in the pool.
     */
    function ilkCount(IIonPool pool) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        Ilk[] storage ilks = $.ilks;

        uint256 slot;
        assembly {
            // Length of ilks array
            slot := ilks.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return The index of the collateral with `ilkAddress`.
     */
    function getIlkIndex(IIonPool pool, address ilkAddress) external view returns (uint8) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        mapping(address => StorageSlot.Uint256Slot) storage ilksSlot =
            _toUint256PointerMapping($.ilkAddresses._inner._positions);

        StorageSlot.Uint256Slot storage ptr = ilksSlot[ilkAddress];

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return uint8(value) - 1;
    }

    /**
     * @return The total amount of normalized debt for collateral with index
     * `ilkIndex`.
     */
    function totalNormalizedDebt(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        IlkSlot0 storage ptr = $.ilks[ilkIndex].slot0;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);

        // Truncate to uint104
        return uint104(value);
    }

    /**
     * @return The `rate` that has been persisted to storage.
     */
    function rateUnaccrued(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        IlkSlot0 storage ptr = $.ilks[ilkIndex].slot0;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        value >>= 104;

        return uint104(value);
    }

    /**
     * @return The timestamp of the last rate update for collateral with index
     * `ilkIndex`.
     */
    function lastRateUpdate(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        IlkSlot0 storage ptr = $.ilks[ilkIndex].slot0;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        value >>= 104 + 104;

        return uint48(value);
    }

    /**
     * @return The spot oracle for collateral with index `ilkIndex`.
     */
    function spot(IIonPool pool, uint8 ilkIndex) external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.AddressSlot storage ptr = $.ilks[ilkIndex].spot;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);

        return address(uint160(value));
    }

    /**
     * @return The debt ceiling for collateral with index `ilkIndex`.
     */
    function debtCeiling(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.Uint256Slot storage ptr = $.ilks[ilkIndex].debtCeiling;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);

        return value;
    }

    /**
     * @return The dust value for collateral with index `ilkIndex`.
     */
    function dust(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.Uint256Slot storage ptr = $.ilks[ilkIndex].dust;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);

        return value;
    }

    /**
     * @return Amount of `gem` that `user` has for collateral with index `ilkIndex`.
     */
    function gem(IIonPool pool, uint8 ilkIndex, address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.Uint256Slot storage ptr = $.gem[ilkIndex][user];

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return The amount of unbacked debt `user` has.
     */
    function unbackedDebt(IIonPool pool, address unbackedDebtor) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.Uint256Slot storage ptr = $.unbackedDebt[unbackedDebtor];

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return Whether or not `operator` is an `operator` on `user`'s positions.
     */
    function isOperator(IIonPool pool, address user, address operator) external view returns (bool) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.Uint256Slot storage ptr = $.isOperator[user][operator];

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value != 0;
    }

    function debtUnaccrued(IIonPool pool) public view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.Uint256Slot storage ptr = $.debt;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @dev This includes unbacked debt.
     * @return The total amount of debt.
     */
    function debt(IIonPool pool) external view returns (uint256) {
        (,,, uint256 totalDebtIncrease,) = pool.calculateRewardAndDebtDistribution();

        return debtUnaccrued(pool) + totalDebtIncrease;
    }

    /**
     * @return The total amount of ETH liquidity in the pool.
     */
    function liquidity(IIonPool pool) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.Uint256Slot storage ptr = $.liquidity;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return The supply cap
     */
    function supplyCap(IIonPool pool) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.Uint256Slot storage ptr = $.supplyCap;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return The total amount of unbacked debt.
     */
    function totalUnbackedDebt(IIonPool pool) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.Uint256Slot storage ptr = $.totalUnbackedDebt;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return The address of the interest rate module.
     */
    function interestRateModule(IIonPool pool) external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.AddressSlot storage ptr = $.interestRateModule;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return address(uint160(value));
    }

    function whitelist(IIonPool pool) external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        StorageSlot.AddressSlot storage ptr = $.whitelist;

        uint256 slot;
        assembly {
            slot := ptr.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        return address(uint160(value));
    }
}
