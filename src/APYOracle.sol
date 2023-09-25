// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IProviderExchangeRate } from "./interfaces/IProviderExchangeRate.sol";

contract APYOracle {
    IProviderExchangeRate public provider;
    uint256 incrementor;
    uint256 apys;
    // we can change 7 to the look_back days we want to use (t0)
    // TODO: change this to a mapping?
    uint256[][7] public historicalAPYs;
    // TODO: hardcode contract addresses for our providers?

    // TODO: how to set this as a float properly?
    uint256 constant PERIODS = 52.142857;

    constructor() {
        incrementor = 0;

    }

    function updateAPY(uint32 providerId) external {
        // fetch exchange rate from provider
        
        // fetch previous exchange rate from historicalAPYs


        // calculate and update APY


        // update historicalAPYs with new exchangeRate and incrementor
        incrementor += 1;

    }

    function getAPY() external view returns (uint256) {
        return apys;
    }
}