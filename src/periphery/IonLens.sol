// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ISpotOracle } from "../interfaces/ISpotOracle.sol";
import { IInterestRate } from "../interfaces/IInterestRate.sol";
import { IIonPool } from "../interfaces/IIonPool.sol";
import { IWhitelist } from "../interfaces/IWhitelist.sol";
import { IIonLens } from "../interfaces/IIonLens.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract IonLens is IIonLens {
    // --- Data ---
    struct Ilk {
        uint104 totalNormalizedDebt; // Total Normalised Debt     [WAD]
        uint104 rate; // Accumulated Rates         [RAY]
        uint48 lastRateUpdate; // block.timestamp of last update; overflows in 800_000 years
        ISpotOracle spot; // Oracle that provides price with safety margin
        uint256 debtCeiling; // Debt Ceiling              [RAD]
        uint256 dust; // Vault Debt Floor            [RAD]
    }

    struct Vault {
        uint256 collateral; // Locked Collateral  [WAD]
        uint256 normalizedDebt; // Normalised Debt    [WAD]
    }

    /// @custom:storage-location erc7201:ion.storage.IonPool
    struct IonPoolStorage {
        Ilk[] ilks;
        // remove() should never be called, it will mess up the ordering
        EnumerableSet.AddressSet ilkAddresses;
        mapping(uint256 ilkIndex => mapping(address user => Vault)) vaults;
        mapping(uint256 ilkIndex => mapping(address user => uint256)) gem; // [WAD]
        mapping(address unbackedDebtor => uint256) unbackedDebt; // [RAD]
        mapping(address user => mapping(address operator => uint256)) isOperator;
        uint256 debt; // Total Debt [RAD]
        uint256 weth; // liquidity in pool [WAD]
        uint256 wethSupplyCap; // [WAD]
        uint256 totalUnbackedDebt; // Total Unbacked WETH  [RAD]
        IInterestRate interestRateModule;
        IWhitelist whitelist;
    }

    // keccak256(abi.encode(uint256(keccak256("ion.storage.IonPool")) - 1)) & ~uint56(0xff))
    // solhint-disable-next-line
    bytes32 private constant IonPoolStorageLocation = 0xceba3d526b4d5afd91d1b752bf1fd37917c20a6daf576bcb41dd1c57c1f67e00;

    bytes4 private constant EXTSLOAD_SELECTOR = 0x1e2eaeaf;

    error SloadFailed();

    function _getIonPoolStorage() internal pure returns (IonPoolStorage storage $) {
        assembly {
            $.slot := IonPoolStorageLocation
        }
    }

    function _getMappingIndexSlot(uint256 key, uint256 mappingSlot) internal pure returns (uint256 slot) {
        assembly ("memory-safe") {
            mstore(0x00, key)
            mstore(0x20, mappingSlot)
            slot := keccak256(0x00, 0x40)
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
     * @return The total amount of collateral in the pool.
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
        mapping(bytes32 => uint256) storage ilks = $.ilkAddresses._inner._positions;

        uint256 mappingsSlot;
        assembly {
            let mappingSlot := ilks.slot
        }

        uint256 ilkAddressUint = uint160(ilkAddress);

        uint256 value = queryPoolSlot(pool, _getMappingIndexSlot({ key: ilkAddressUint, mappingSlot: mappingsSlot }));
        return uint8(value) - 1;
    }

    /**
     * @return The total amount of normalized debt for collateral with index
     * `ilkIndex`.
     */
    function totalNormalizedDebt(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        Ilk storage ilk = $.ilks[ilkIndex];

        uint256 slot;
        assembly {
            slot := ilk.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        uint256 mask = type(uint104).max;
        return value & mask;
    }

    /**
     * @return The `rate` that has been persisted to storage.
     */
    function rateUnaccrued(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        Ilk storage ilk = $.ilks[ilkIndex];

        uint256 slot;
        assembly {
            slot := ilk.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        value >>= 104;
        uint256 mask = type(uint104).max;
        return value & mask;
    }

    /**
     * @return The timestamp of the last rate update for collateral with index
     * `ilkIndex`.
     */
    function lastRateUpdate(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        Ilk storage ilk = $.ilks[ilkIndex];

        uint256 slot;
        assembly {
            slot := ilk.slot
        }

        uint256 value = queryPoolSlot(pool, slot);
        value >>= 104 + 104;
        uint256 mask = type(uint48).max;
        return value & mask;
    }

    /**
     * @return The spot oracle for collateral with index `ilkIndex`.
     */
    function spot(IIonPool pool, uint8 ilkIndex) external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        Ilk storage ilk = $.ilks[ilkIndex];

        uint256 slot;
        assembly {
            slot := add(ilk.slot, 1)
        }

        uint256 value = queryPoolSlot(pool, slot);
        return address(uint160(value));
    }

    /**
     * @return The debt ceiling for collateral with index `ilkIndex`.
     */
    function debtCeiling(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        Ilk storage ilk = $.ilks[ilkIndex];

        uint256 slot;
        assembly {
            slot := add(ilk.slot, 2)
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return The dust value for collateral with index `ilkIndex`.
     */
    function dust(IIonPool pool, uint8 ilkIndex) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        Ilk storage ilk = $.ilks[ilkIndex];

        uint256 slot;
        assembly {
            slot := add(ilk.slot, 3)
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return Amount of `gem` that `user` has for collateral with index `ilkIndex`.
     */
    function gem(IIonPool pool, uint8 ilkIndex, address user) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        mapping(uint256 ilkIndex => mapping(address user => uint256)) storage gemMapping = $.gem;

        uint256 mappingSlot;
        assembly {
            mappingSlot := gemMapping.slot
        }

        uint256 userUint = uint160(user);

        uint256 mappingSlot1 = _getMappingIndexSlot({ key: ilkIndex, mappingSlot: mappingSlot });
        uint256 mappingSlot2 = _getMappingIndexSlot({ key: userUint, mappingSlot: mappingSlot1 });

        uint256 value = queryPoolSlot(pool, mappingSlot2);
        return value;
    }

    /**
     * @return The amount of unbacked debt `user` has.
     */
    function unbackedDebt(IIonPool pool, address unbackedDebtor) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        mapping(address unbackedDebtor => uint256) storage debtMapping = $.unbackedDebt; // [RAD]

        uint256 mappingSlot;
        assembly {
            mappingSlot := debtMapping.slot
        }

        uint256 value =
            queryPoolSlot(pool, _getMappingIndexSlot({ key: uint160(unbackedDebtor), mappingSlot: mappingSlot }));
        return value;
    }

    /**
     * @return Whether or not `operator` is an `operator` on `user`'s positions.
     */
    function isOperator(IIonPool pool, address user, address operator) external view returns (bool) {
        IonPoolStorage storage $ = _getIonPoolStorage();
        mapping(address user => mapping(address operator => uint256)) storage operatorMapping = $.isOperator;

        uint256 mappingSlot;
        assembly {
            mappingSlot := operatorMapping.slot
        }

        uint256 userUint = uint160(user);
        uint256 operatorUint = uint160(operator);

        uint256 mappingSlot1 = _getMappingIndexSlot({ key: userUint, mappingSlot: mappingSlot });
        uint256 mappingSlot2 = _getMappingIndexSlot({ key: operatorUint, mappingSlot: mappingSlot1 });
        uint256 value = queryPoolSlot(pool, mappingSlot2);
        return value != 0;
    }

    function debtUnaccrued(IIonPool pool) public view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 slot;
        assembly {
            slot := add($.slot, 6)
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
    function weth(IIonPool pool) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 slot;
        assembly {
            slot := add($.slot, 7)
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return The supply cap
     */
    function wethSupplyCap(IIonPool pool) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 slot;
        assembly {
            slot := add($.slot, 8)
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return The total amount of unbacked debt.
     */
    function totalUnbackedDebt(IIonPool pool) external view returns (uint256) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 slot;
        assembly {
            slot := add($.slot, 9)
        }

        uint256 value = queryPoolSlot(pool, slot);
        return value;
    }

    /**
     * @return The address of the interest rate module.
     */
    function interestRateModule(IIonPool pool) external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 slot;
        assembly {
            slot := add($.slot, 10)
        }

        uint256 value = queryPoolSlot(pool, slot);
        return address(uint160(value));
    }

    function whitelist(IIonPool pool) external view returns (address) {
        IonPoolStorage storage $ = _getIonPoolStorage();

        uint256 slot;
        assembly {
            slot := add($.slot, 11)
        }

        uint256 value = queryPoolSlot(pool, slot);
        return address(uint160(value));
    }
}
