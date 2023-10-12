// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { safeconsole as console } from "forge-std/safeconsole.sol";
import { IonPool } from "../../src/IonPool.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { InterestRate } from "../../src/InterestRate.sol";
import { BaseTestSetup } from "../helpers/BaseTestSetup.sol";
import { IYieldOracle } from "../.././src/interfaces/IYieldOracle.sol";

contract IonPoolExposed is IonPool {
    constructor(
        address _underlying,
        address _treasury,
        uint8 decimals_,
        string memory name_,
        string memory symbol_,
        address initialDefaultAdmin,
        InterestRate _interestRateModule
    ) 
    // IonPool(_underlying, _treasury, decimals_, name_, symbol_, initialDefaultAdmin, _interestRateModule)
    { }

    function add(uint256 x, int256 y) external pure returns (uint256 z) {
        return _add(x, y);
    }

    function sub(uint256 x, int256 y) external pure returns (uint256 z) {
        return _sub(x, y);
    }
}

/**
 * @dev Differential test of IonPool's math functions against the dss math functions
 */
contract IonPool_MathDiffTest is BaseTestSetup {
    using SafeCast for uint256;

    IonPoolExposed ionPool;

    constructor() {
        InterestRate i;
        ionPool = new IonPoolExposed(address(underlying), TREASURY, DECIMALS, NAME, SYMBOL, address(this), i);
    }

    /**
     * @dev Mul test
     */
    function testDifferential_mul(uint256 x, int256 y) external {
        // Bypass type-checking XD
        (bool success,) =
            address(this).call(abi.encodeWithSelector(this.diffTest.selector, this.mulDss, this.mulSol, x, y));
        require(success);
    }

    function mulDss(uint256 x, int256 y) public pure returns (int256 z) {
        z = int256(x) * y;
        require(int256(x) >= 0);
        require(y == 0 || z / y == int256(x));
    }

    function mulSol(uint256 x, int256 y) public pure returns (int256 z) {
        z = x.toInt256() * y;
    }

    /**
     * @dev Sub test
     */
    function testDifferential_sub(uint256 x, int256 y) external {
        diffTest(this.subDss, ionPool.sub, x, y);
    }

    function subDss(uint256 x, int256 y) public pure returns (uint256 z) {
        unchecked {
            z = x - uint256(y);
        }
        require(y <= 0 || z <= x);
        require(y >= 0 || z >= x);
    }

    function testDifferential_add(uint256 x, int256 y) external {
        diffTest(this.addDss, ionPool.add, x, y);
    }

    function addDss(uint256 x, int256 y) public pure returns (uint256 z) {
        unchecked {
            z = x + uint256(y);
        }
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }

    function diffTest(
        function(uint256, int256) external pure returns (uint256) dssImpl,
        function(uint256, int256) external pure returns (uint256) solImpl,
        uint256 x,
        int256 y
    )
        public
    {
        (bool successDss, bytes memory returnDataDss) =
            dssImpl.address.call(abi.encodeWithSelector(dssImpl.selector, x, y));
        (bool successSol, bytes memory returnDataSol) =
            solImpl.address.call(abi.encodeWithSelector(solImpl.selector, x, y));

        assertEq(successDss, successSol);

        if (successDss) {
            assertEq(abi.decode(returnDataDss, (uint256)), abi.decode(returnDataSol, (uint256)));
        }
    }
}
