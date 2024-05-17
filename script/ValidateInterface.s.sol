// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IonPool } from "../src/IonPool.sol";
import { ReserveOracle } from "../src/oracles/reserve/ReserveOracle.sol";
import { SpotOracle } from "../src/oracles/spot/SpotOracle.sol";
import { YieldOracle } from "../src/YieldOracle.sol";
import { InterestRate } from "../src/InterestRate.sol";
import { Whitelist } from "../src/Whitelist.sol";
import { GemJoin } from "../src/join/GemJoin.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Validates that an address implements the expected interface by
 * checking there is code at the provided address and calling a few functions.
 */
abstract contract ValidateInterface {
    function _validateInterfaceIonPool(IonPool ionPool) internal view {
        require(address(ionPool).code.length > 0, "ionPool address must have code");
        ionPool.balanceOf(address(this));
    }

    function _validateInterface(IERC20 ilkAddress) internal view {
        require(address(ilkAddress).code.length > 0, "ilk address must have code");
        ilkAddress.balanceOf(address(this));
        ilkAddress.totalSupply();
        ilkAddress.allowance(address(this), address(this));
    }

    function _validateInterface(ReserveOracle reserveOracle) internal view {
        require(address(reserveOracle).code.length > 0, "reserveOracle address must have code");
        reserveOracle.getProtocolExchangeRate();
        reserveOracle.QUORUM();
        reserveOracle.FEED0();
    }

    function _validateInterface(SpotOracle spotOracle) internal view {
        require(address(spotOracle).code.length > 0, "spotOracle address must have code");
        spotOracle.getPrice();
        spotOracle.getSpot();
    }

    function _validateInterface(YieldOracle yieldOracle) internal view {
        require(address(yieldOracle).code.length > 0, "yieldOracle address must have code");
        yieldOracle.apys(0);
    }

    function _validateInterface(InterestRate interestRateModule) internal view {
        require(address(interestRateModule).code.length > 0, "interestRateModule address must have code");
        interestRateModule.COLLATERAL_COUNT();
        interestRateModule.YIELD_ORACLE();
        interestRateModule.calculateInterestRate(0, 0, 0);
    }

    function _validateInterface(Whitelist whitelist) internal view {
        require(address(whitelist).code.length > 0, "whitelist address must have code");
        whitelist.lendersRoot();
        whitelist.borrowersRoot(0);
    }

    function _validateInterface(GemJoin gemJoin) internal view {
        require(address(gemJoin).code.length > 0, "gemJoin address must have code");
        gemJoin.GEM();
        gemJoin.POOL();
        gemJoin.ILK_INDEX();
        gemJoin.totalGem();
    }
}
