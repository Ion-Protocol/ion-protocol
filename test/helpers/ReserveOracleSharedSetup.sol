// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import { RoundedMath } from "src/libraries/math/RoundedMath.sol";
import { StEthReserveOracle } from "src/oracles/reserve/StEthReserveOracle.sol";
import { ILido, IWstEth } from "src/interfaces/ProviderInterfaces.sol";

import { ERC20PresetMinterPauser } from "test/helpers/ERC20PresetMinterPauser.sol";
import { IonPoolSharedSetup } from "test/helpers/IonPoolSharedSetup.sol";
import { RoundedMath, WAD, RAY } from "src/libraries/math/RoundedMath.sol";

contract MockFeed {
    mapping(uint8 ilkIndex => uint256 exchangeRate) public exchangeRates;

    constructor() { }

    function setExchangeRate(uint8 _ilkIndex, uint256 _exchangeRate) public {
        exchangeRates[_ilkIndex] = _exchangeRate;
    }

    function getExchangeRate(uint8 _ilkIndex) public returns (uint256) {
        return exchangeRates[_ilkIndex];
    }
}

// fork tests for integrating with external contracts
contract ReserveOracleSharedSetup is IonPoolSharedSetup {
    using RoundedMath for *;

    uint8 constant STETH_ILK_INDEX = 0;
    uint8 constant SWETH_ILK_INDEX = 1;
    uint8 constant ETHX_ILK_INDEX = 2;

    address constant LIDO = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    bytes32 constant LIDO_CL_BALANCE_SLOT = 0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483;
    bytes32 constant LIDO_TOTAL_SHARES_SLOT = 0xe3b4b636e601189b5f4c6742edf2538ac12bb61ed03e6da26949d69838fa447e;

    address constant SWETH_PROTOCOL_FEED = 0xf951E335afb289353dc249e82926178EaC7DEd78;

    address constant ETHX_PROTOCOL_FEED = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;

    // fork configs

    string public MAINNET_RPC_URL = vm.envString("MAINNET_ARCHIVE_RPC_URL");

    uint256 constant BLOCK_NUMBER = 18_372_927;

    uint256 mainnetFork;

    ERC20PresetMinterPauser mockToken;

    function setUp() public override {
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL); // specify blockheight?
        vm.rollFork(BLOCK_NUMBER);

        super.setUp();

        ERC20PresetMinterPauser mockToken = new ERC20PresetMinterPauser("Mock LST", "mLST");
    }
}
