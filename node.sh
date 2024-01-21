# Run 
# 1. Set up testnet
#    - via `anvil --fork-url $MAINNET_ARCHIVE_RPC_URL --chain-id 31337` or Tenderly Devnet. 
# 2. Set the env variables. 
# 3. Run `bash node.sh` 
# 4. forge script script/__TestFlashLeverage.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY 

source .env 

# Env Variables
echo "ETH_FROM: " $ETH_FROM
echo "PRIVATE_KEY: " $PRIVATE_KEY  
echo "RPC_URL: " $RPC_URL
echo "CHAIN_ID: " $CHAIN_ID
# Set Chain ID based on deployment route 
if [ $RPC_URL == "http://localhost:8545" ]; then
    chain_id=31337
    private_key="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" # anvil private key
    initial_admin="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" # anvil public key
else 
    chain_id=$CHAIN_ID
    private_key=$PRIVATE_KEY
    initial_admin=$ETH_FROM
fi

echo -e "chain_id: $chain_id"
echo -e "private_key: $private_key\n"

# Deploy YieldOracle
echo "DEPLOYING YIELD ORACLE..."
CHAIN_ID=1 forge script script/01_DeployYieldOracle.s.sol -s 'configureDeployment()' --ffi
forge script script/01_DeployYieldOracle.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow

# Copy YieldOracle address from latest deployment and dump it into InterestRate deployment config
yield_oracle_addr=$(jq '.returns.yieldOracle.value' "broadcast/01_DeployYieldOracle.s.sol/$chain_id/run-latest.json" | xargs)
jq --arg address "$yield_oracle_addr" '. + { "YieldOracleAddress": $address }' deployment-config/02_InterestRate.json >temp.json && mv temp.json deployment-config/02_InterestRate.json

# Deploy InterestRate module and whitelist
echo "DEPLOYING INTEREST RATE MODULE..."
forge script script/02_DeployInterestRateModule.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow
echo "DEPLOYING WHITELIST"
forge script script/03_DeployWhitelist.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow

# Copy InterestRate and whitelist addresses from latest deployment and dump them into IonPool deployment config
interest_rate_addr=$(jq '.returns.interestRateModule.value' "broadcast/02_DeployInterestRateModule.s.sol/$chain_id/run-latest.json" | xargs)
whitelist_addr=$(jq '.returns.whitelist.value' "broadcast/03_DeployWhitelist.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg interest_rate "$interest_rate_addr" --arg whitelist "$whitelist_addr" --arg initial_admin "$initial_admin" '. + { "initialDefaultAdmin": $initial_admin, "interestRateModule": $interest_rate, whitelist: $whitelist }' deployment-config/04_IonPool.json >temp.json && mv temp.json deployment-config/04_IonPool.json

# Deploy IonPool!
echo "DEPLOYING ION POOL..."
forge script script/04_DeployIonPool.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow

# Deploy Oracles
echo "DEPLOYING ORACLES..."
forge script script/05_DeployInitialReserveAndSpotOracles.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow

# # Copy IonPool address from latest deployment and dump it into initial setup config
ionpool_addr=$(jq '.returns.ionPool.value' "broadcast/04_DeployIonPool.s.sol/$chain_id/run-latest.json" | xargs)
wst_eth_spot=$(jq '.returns.wstEthSpotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
ethx_spot=$(jq '.returns.ethXSpotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
sw_eth_spot=$(jq '.returns.swEthSpotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg ionpool_addr "$ionpool_addr" --arg wst_eth_spot "$wst_eth_spot" --arg ethx_spot "$ethx_spot" --arg sw_eth_spot "$sw_eth_spot" '. + { "ionPool": $ionpool_addr, "wstEthSpot": $wst_eth_spot, "ethXSpot": $ethx_spot, "swEthSpot": $sw_eth_spot }' deployment-config/06_SetupInitialCollaterals.json >temp.json && mv temp.json deployment-config/06_SetupInitialCollaterals.json

# Setup initial collaterals
forge script script/06_SetupInitialCollaterals.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow

jq --arg ionpool_addr "$ionpool_addr" --arg initial_admin "$initial_admin" '. + { "ionPool": $ionpool_addr, "owner": $initial_admin }' deployment-config/07_DeployInitialGemJoins.json >temp.json && mv temp.json deployment-config/07_DeployInitialGemJoins.json

# Deploy GemJoins
forge script script/07_DeployInitialGemJoins.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow

wst_eth_join_addr=$(jq '.returns.wstEthGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)
ethx_join_addr=$(jq '.returns.ethXGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)
sw_eth_join_addr=$(jq '.returns.swEthGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg ionpool_addr "$ionpool_addr" --arg wst_eth_join "$wst_eth_join_addr" --arg ethx_join "$ethx_join_addr" --arg sw_eth_join "$sw_eth_join_addr" --arg whitelist "$whitelist_addr" '. + { "ionPool": $ionpool_addr, "wstEthGemJoin": $wst_eth_join, "ethXGemJoin": $ethx_join, "swEthGemJoin": $sw_eth_join, whitelist: $whitelist }' deployment-config/08_DeployInitialHandlers.json >temp.json && mv temp.json deployment-config/08_DeployInitialHandlers.json

# Deploy Handlers
forge script script/08_DeployInitialHandlers.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow --tc DeployInitialHandlersScript

# Deploy Liquidation
echo "DEPLOYING LIQUIDATION..."
protocol_addr=$(jq .treasury "deployment-config/04_IonPool.json" | xargs) # copies from IonPool configuration
wst_eth_reserve=$(jq '.returns.wstEthReserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
ethx_reserve=$(jq '.returns.ethXReserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
sw_eth_reserve=$(jq '.returns.swEthReserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
jq --arg ionpool_addr "$ionpool_addr" \
--arg protocol_addr "$protocol_addr" \
--arg wst_eth_reserve "$wst_eth_reserve" \
--arg ethx_reserve "$ethx_reserve" \
--arg sw_eth_reserve "$sw_eth_reserve" \
'. + { "ionPool": $ionpool_addr, "protocol": $protocol_addr, "reserveOracles": [$wst_eth_reserve, $ethx_reserve, $sw_eth_reserve] }' deployment-config/09_Liquidation.json > temp.json && mv temp.json deployment-config/09_Liquidation.json

forge script script/09_DeployLiquidation.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow --tc DeployLiquidationScript

# Deploy Ion Zapper
echo "DEPLOYING ION ZAPPER..."
ionpool_addr=$(jq '.returns.ionPool.value' "broadcast/04_DeployIonPool.s.sol/$chain_id/run-latest.json" | xargs)
weth_addr="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
st_eth_addr="0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
wst_eth_addr="0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"
wst_eth_join_addr=$(jq '.returns.wstEthGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)
whitelist_addr=$(jq '.returns.whitelist.value' "broadcast/03_DeployWhitelist.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg ionpool_addr "$ionpool_addr" \
--arg weth_addr "$weth_addr" \
--arg st_eth_addr "$st_eth_addr" \
--arg wst_eth_addr "$wst_eth_addr" \
--arg wst_eth_join_addr "$wst_eth_join_addr" \
--arg whitelist_addr "$whitelist_addr" \
'. + {
    "ionPool": $ionpool_addr,
    "weth": $weth_addr,
    "stEth": $st_eth_addr,
    "wstEth": $wst_eth_addr,
    "wstEthJoin": $wst_eth_join_addr,
    "whitelist": $whitelist_addr
}' deployment-config/10_IonZapper.json > temp.json && mv temp.json deployment-config/10_IonZapper.json

forge script script/10_DeployIonZapper.s.sol --rpc-url $RPC_URL --private-key $private_key --broadcast --slow --tc DeployIonZapperScript

bash gen-env.sh 