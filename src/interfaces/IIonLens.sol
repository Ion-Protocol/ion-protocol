// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { IIonPool } from "./IIonPool.sol";

interface IIonLens {
    function queryPoolSlot(IIonPool pool, uint256 slot) external view returns (uint256 value);

    function ilkCount(IIonPool pool) external view returns (uint256);

    function getIlkIndex(IIonPool pool, address ilkAddress) external view returns (uint8);

    function totalNormalizedDebt(IIonPool pool, uint8 ilkIndex) external view returns (uint256);

    function rateUnaccrued(IIonPool pool, uint8 ilkIndex) external view returns (uint256);

    function lastRateUpdate(IIonPool pool, uint8 ilkIndex) external view returns (uint256);

    function spot(IIonPool pool, uint8 ilkIndex) external view returns (address);

    function debtCeiling(IIonPool pool, uint8 ilkIndex) external view returns (uint256);

    function dust(IIonPool pool, uint8 ilkIndex) external view returns (uint256);

    function gem(IIonPool pool, uint8 ilkIndex, address user) external view returns (uint256);

    function unbackedDebt(IIonPool pool, address unbackedDebtor) external view returns (uint256);

    function isOperator(IIonPool pool, address user, address operator) external view returns (bool);

    function debtUnaccrued(IIonPool pool) external view returns (uint256);

    function debt(IIonPool pool) external view returns (uint256);

    function liquidity(IIonPool pool) external view returns (uint256);

    function supplyCap(IIonPool pool) external view returns (uint256);

    function totalUnbackedDebt(IIonPool pool) external view returns (uint256);

    function interestRateModule(IIonPool pool) external view returns (address);

    function whitelist(IIonPool pool) external view returns (address);
}
