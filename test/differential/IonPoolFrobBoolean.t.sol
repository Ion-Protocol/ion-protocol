// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

//TODO: License and versioning

import { Test } from "forge-std/Test.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract IonPool_FrobBooleanTest is Test {
    // Contract will use 128 bit types to avoid overflows
    using SafeCast for uint256;

    struct Ilk {
        uint128 totalNormalizedDebt;
        uint128 debtCeiling;
        uint128 spot;
        uint128 dust;
    }

    struct Vault {
        uint128 collateral;
        uint128 normalizedDebt;
    }

    function testFuzz_FrobBoolean1(
        int128 changeInNormalizedDebt,
        uint128 ilkRate,
        uint128 debt,
        uint128 globalDebtCeiling,
        Ilk memory ilk
    )
        external
    {
        assertEq(
            either(
                changeInNormalizedDebt <= 0,
                both(uint256(ilk.totalNormalizedDebt) * uint256(ilkRate) <= ilk.debtCeiling, debt <= globalDebtCeiling)
            ),
            !both(
                changeInNormalizedDebt > 0,
                either(uint256(ilk.totalNormalizedDebt) * uint256(ilkRate) > ilk.debtCeiling, debt > globalDebtCeiling)
            )
        );
    }

    function testFuzz_FrobBoolean2(
        int128 changeInNormalizedDebt,
        int128 changeInCollateral,
        uint128 newDebtInVault,
        Ilk memory ilk,
        Vault memory vault
    )
        external
    {
        assertEq(
            either(
                both(changeInNormalizedDebt <= 0, changeInCollateral >= 0),
                newDebtInVault <= uint256(vault.collateral) * uint256(ilk.spot)
            ),
            !both(
                either(changeInNormalizedDebt > 0, changeInCollateral < 0),
                newDebtInVault > uint256(vault.collateral) * uint256(ilk.spot)
            )
        );
    }

    function testFuzz_FrobBoolean3(int128 changeInNormalizedDebt, int128 changeInCollateral, bool approved) external {
        assertEq(
            either(both(changeInNormalizedDebt <= 0, changeInCollateral >= 0), approved),
            !both(either(changeInNormalizedDebt > 0, changeInCollateral < 0), !approved)
        );
    }

    function testFuzz_FrobBoolean4(int128 changeInCollateral, bool approved) external {
        assertEq(either(changeInCollateral <= 0, approved), !both(changeInCollateral > 0, !approved));
    }

    function testFuzz_FrobBoolean5(int128 changeInNormalizedDebt, bool approved) external {
        assertEq(either(changeInNormalizedDebt >= 0, approved), !both(changeInNormalizedDebt < 0, !approved));
    }

    function testFuzz_FrobBoolean6(uint256 newDebtInVault, Ilk memory ilk, Vault memory vault) external {
        assertEq(
            either(vault.normalizedDebt == 0, newDebtInVault >= ilk.dust),
            !both(vault.normalizedDebt != 0, newDebtInVault < ilk.dust)
        );
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
}
