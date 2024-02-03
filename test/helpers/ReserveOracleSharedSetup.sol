// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { ETHER_FI_LIQUIDITY_POOL_ADDRESS } from "../../src/Constants.sol";
import { WadRayMath } from "../../src/libraries/math/WadRayMath.sol";
import { IWstEth, IStaderStakePoolsManager, IEtherFiLiquidityPool } from "../../src/interfaces/ProviderInterfaces.sol";

import { ERC20PresetMinterPauser } from "../helpers/ERC20PresetMinterPauser.sol";
import { IonPoolSharedSetup } from "../helpers/IonPoolSharedSetup.sol";

// fork tests for integrating with external contracts
contract ReserveOracleSharedSetup is IonPoolSharedSetup {
    using WadRayMath for *;

    uint8 constant STETH_ILK_INDEX = 0;
    uint8 constant SWETH_ILK_INDEX = 1;
    uint8 constant ETHX_ILK_INDEX = 2;

    // default reserve oracle configs
    uint256 constant MAX_CHANGE = 1e27; // 100%
    uint8 constant ILK_INDEX = 0;
    uint8 constant QUORUM = 0;

    address constant LIDO = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    bytes32 constant LIDO_CL_BALANCE_SLOT = 0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483;
    bytes32 constant LIDO_TOTAL_SHARES_SLOT = 0xe3b4b636e601189b5f4c6742edf2538ac12bb61ed03e6da26949d69838fa447e;

    address constant SWETH = 0xf951E335afb289353dc249e82926178EaC7DEd78;
    bytes32 constant SWETH_TO_ETH_RATE_SLOT = 0x0000000000000000000000000000000000000000000000000000000000000095;

    address constant STADER_STAKE_POOLS_MANAGER = 0xcf5EA1b38380f6aF39068375516Daf40Ed70D299;
    address constant STADER_ORACLE = 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737;
    bytes32 constant STADER_ORACLE_TOTAL_ETH_BALANCE_SLOT =
        0x0000000000000000000000000000000000000000000000000000000000000103;
    bytes32 constant STADER_ORACLE_TOTAL_SUPPLY_SLOT =
        0x0000000000000000000000000000000000000000000000000000000000000104;

    bytes32 constant EETH_LIQUIDITY_POOL_TOTAL_VALUE_SLOT =
        0x00000000000000000000000000000000000000000000000000000000000000cf; // uint128 totalValueInLp, uint128
        // totalValueOutOfLp
    bytes32 constant EETH_TOTAL_VALUE_MASK = 0x00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    // fork configs

    string public MAINNET_RPC_URL = vm.envString("MAINNET_ARCHIVE_RPC_URL");

    uint256 constant BLOCK_NUMBER = 18_372_927;

    uint256 public blockNumber;

    uint256 mainnetFork;

    ERC20PresetMinterPauser mockToken;

    function setUp() public virtual override {
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL, blockNumber);

        super.setUp();

        mockToken = new ERC20PresetMinterPauser("Mock LST", "mLST");
    }

    function changeStaderOracleExchangeRate(
        uint256 totalEthBalance,
        uint256 totalSupply
    )
        internal
        returns (uint256 newExchangeRate)
    {
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_ETH_BALANCE_SLOT, bytes32(totalEthBalance));
        vm.store(STADER_ORACLE, STADER_ORACLE_TOTAL_SUPPLY_SLOT, bytes32(totalSupply));
        newExchangeRate = IStaderStakePoolsManager(STADER_STAKE_POOLS_MANAGER).getExchangeRate();
    }

    function changeStEthClBalance(uint256 clBalance) internal returns (uint256 newExchangeRate) {
        vm.store(LIDO, LIDO_CL_BALANCE_SLOT, bytes32(clBalance));
        assertEq(uint256(vm.load(LIDO, LIDO_CL_BALANCE_SLOT)), clBalance);
        newExchangeRate = IWstEth(WSTETH).stEthPerToken();
    }

    function changeSwEthExchangeRate(uint256 exchangeRate) internal {
        // set swETH exchange rate to be lower
        vm.store(SWETH, SWETH_TO_ETH_RATE_SLOT, bytes32(exchangeRate));
    }

    function changeWeEthLpBalance(uint256 lpBalanceDiff) internal {
        uint256 totalValueOutOfLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueOutOfLp();
        uint256 totalValueInLp = ETHER_FI_LIQUIDITY_POOL_ADDRESS.totalValueInLp();

        bytes32 newTotalValueInLp = bytes32(totalValueInLp) << 128;

        bytes32 newTotalValueOutOfLp = bytes32(uint256(totalValueOutOfLp - lpBalanceDiff));

        bytes32 newTotalValue = newTotalValueInLp | newTotalValueOutOfLp;

        // reduce rebase share values in EtherFi
        vm.store(address(ETHER_FI_LIQUIDITY_POOL_ADDRESS), EETH_LIQUIDITY_POOL_TOTAL_VALUE_SLOT, bytes32(newTotalValue));
    }
}
