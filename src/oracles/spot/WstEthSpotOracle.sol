// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SpotOracle } from "../../oracles/spot/SpotOracle.sol";
import { IChainlink } from "../../interfaces/IChainlink.sol";
import { IWstEth } from "../../interfaces/ProviderInterfaces.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @notice The wstETH spot oracle.
 *
 * @custom:security-contact security@molecularlabs.io
 */
contract WstEthSpotOracle is SpotOracle {
    using SafeCast for int256;

    IChainlink public immutable ST_ETH_TO_ETH_CHAINLINK;
    IWstEth public immutable WST_ETH;

    /**
     * @notice Creates a new `WstEthSpotOracle` instance.
     * @param _ltv The loan to value ratio for wstETH.
     * @param _reserveOracle The associated reserve oracle.
     * @param _stEthToEthChainlink The chainlink price feed for stETH/ETH.
     * @param _wstETH The wstETH contract address.
     */
    constructor(
        uint256 _ltv,
        address _reserveOracle,
        address _stEthToEthChainlink,
        address _wstETH
    )
        SpotOracle(_ltv, _reserveOracle)
    {
        ST_ETH_TO_ETH_CHAINLINK = IChainlink(_stEthToEthChainlink);
        WST_ETH = IWstEth(_wstETH);
    }

    /**
     * @notice Gets the price of wstETH in terms of ETH.
     * @dev Because the collateral amount in the core contract is denominated in
     * amount of wstETH tokens, spot needs to equal (stETH/wstETH) * (ETH/stETH)
     * * liquidationThreshold. If the beaconchain reserve decreases, the wstETH
     * to stEth conversion will be directly impacted, but the stEth to Eth
     * conversion will simply be determined by the chainlink price oracle.
     * @return ethPerWstEth price of wstETH in ETH. [WAD]
     */
    function getPrice() public view override returns (uint256 ethPerWstEth) {
        // get price from the protocol feed
        (, int256 _ethPerStEth,,,) = ST_ETH_TO_ETH_CHAINLINK.latestRoundData(); // price of stETH denominated in ETH
        uint256 ethPerStEth = _ethPerStEth.toUint256();
        // collateral * wstEthInEth = collateralInEth
        ethPerWstEth = WST_ETH.getStETHByWstETH(ethPerStEth); // stEth per wstETH
    }
}
