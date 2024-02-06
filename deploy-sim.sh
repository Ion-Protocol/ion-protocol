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
echo "RPC_URL: " $DEPLOY_SIM_RPC_URL
echo "CHAIN_ID: " $CHAIN_ID
# Set Chain ID based on deployment route 
if [ $DEPLOY_SIM_RPC_URL == "http://localhost:8545" ]; then
    chain_name='anvil' 
    chain_id=31337
    private_key="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" # anvil private key
else 
    chain_name='tenderly'
    chain_id=$TENDERLY_CHAIN_ID
    private_key=$PRIVATE_KEY
fi

# sanity check all required variables 

echo -e "chain_name: $chain_name" 
echo -e "chain_id: $chain_id"
echo -e "private_key: $private_key\n"

# Start anvil and run with tests if specified
# Clear code at the IonPool CreateX Address
# Fund the ETH_FROM address with gas token 

# Deploy YieldOracle
echo "DEPLOYING YIELD ORACLE..."
bun run 01_DeployYieldOracle:deployment:configure 
bun run 01_DeployYieldOracle:deployment:deploy:$chain_name

# Copy YieldOracle address from latest deployment and dump it into InterestRate deployment config
yield_oracle_addr=$(jq '.returns.yieldOracle.value' "broadcast/01_DeployYieldOracle.s.sol/$chain_id/run-latest.json" | xargs)
jq --arg address "$yield_oracle_addr" '. + { "YieldOracleAddress": $address }' deployment-config/02_DeployInterestRateModule.json >temp.json && mv temp.json deployment-config/02_DeployInterestRateModule.json

# Deploy InterestRate module and whitelist
echo "DEPLOYING INTEREST RATE MODULE..."
bun run 02_DeployInterestRateModule:deployment:deploy:$chain_name

echo "DEPLOYING WHITELIST"
bun run 03_DeployWhitelist:deployment:deploy:$chain_name

# Copy InterestRate and whitelist addresses from latest deployment and dump them into IonPool deployment config
interest_rate_addr=$(jq '.returns.interestRateModule.value' "broadcast/02_DeployInterestRateModule.s.sol/$chain_id/run-latest.json" | xargs)
whitelist_addr=$(jq '.returns.whitelist.value' "broadcast/03_DeployWhitelist.s.sol/$chain_id/run-latest.json" | xargs)
jq --arg interest_rate "$interest_rate_addr" --arg whitelist "$whitelist_addr" '. + { "interestRateModule": $interest_rate, whitelist: $whitelist }' deployment-config/04_DeployIonPool.json >temp.json && mv temp.json deployment-config/04_DeployIonPool.json

# Deploy IonPool!
echo "DEPLOYING ION POOL..."
bun run 04_DeployIonPool:deployment:deploy:$chain_name

# Deploy Oracles
echo "DEPLOYING ORACLES..."
bun run 05_DeployInitialReserveAndSpotOracles:deployment:deploy:$chain_name

# Copy IonPool address from latest deployment and dump it into initial setup config
ionpool_addr=$(jq '.returns.ionPool.value' "broadcast/04_DeployIonPool.s.sol/$chain_id/run-latest.json" | xargs)
spot_oracle=$(jq '.returns.spotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg ionpool_addr "$ionpool_addr" --arg spot_oracle "$spot_oracle" '. + { "ionPool": $ionpool_addr, "spotOracle": $spot_oracle }' deployment-config/06_DeployInitialCollateralsSetUp.json >temp.json && mv temp.json deployment-config/06_DeployInitialCollateralsSetUp.json
# jq --arg ionpool_addr "$ionpool_addr" --arg wst_eth_spot "$wst_eth_spot" --arg ethx_spot "$ethx_spot" --arg sw_eth_spot "$sw_eth_spot" '. + { "ionPool": $ionpool_addr, "wstEthSpot": $wst_eth_spot, "ethXSpot": $ethx_spot, "swEthSpot": $sw_eth_spot }' deployment-config/06_SetupInitialCollaterals.json >temp.json && mv temp.json deployment-config/06_SetupInitialCollaterals.json

# Setup initial collaterals
bun run 06_DeployInitialCollateralsSetUp:deployment:deploy:$chain_name

jq --arg ionpool_addr "$ionpool_addr" '. + { "ionPool": $ionpool_addr }' deployment-config/07_DeployInitialGemJoins.json >temp.json && mv temp.json deployment-config/07_DeployInitialGemJoins.json

# Deploy GemJoins
bun run 07_DeployInitialGemJoins:deployment:deploy:$chain_name

gem_join_addr=$(jq '.returns.gemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg ionpool_addr "$ionpool_addr" --arg gem_join "$gem_join_addr" --arg whitelist "$whitelist_addr" '. + { "ionPool": $ionpool_addr, "gemJoin": $gem_join, whitelist: $whitelist }' deployment-config/08_DeployInitialHandlers.json >temp.json && mv temp.json deployment-config/08_DeployInitialHandlers.json

# Deploy Handlers
bun run 08_DeployInitialHandlers:deployment:deploy:$chain_name

# Deploy Liquidation
echo "DEPLOYING LIQUIDATION..."
reserve_oracle=$(jq '.returns.reserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg ionpool_addr "$ionpool_addr" \
--arg reserve_oracle "$reserve_oracle" \
'. + { "ionPool": $ionpool_addr }' deployment-config/09_DeployLiquidation.json > temp.json && mv temp.json deployment-config/09_DeployLiquidation.json

bun run 09_DeployLiquidation:deployment:deploy:$chain_name

# DeployAdminTransfer and tests 

# # write all the deployed addresses to json
# wst_eth_handler_addr=$(jq '.returns.wstEthHandler.value' "broadcast/08_DeployInitialHandlers.s.sol/$chain_id/run-latest.json" | xargs)
# eth_x_handler_addr=$(jq '.returns.ethXHandler.value' "broadcast/08_DeployInitialHandlers.s.sol/$chain_id/run-latest.json" | xargs)
# sw_eth_handler_addr=$(jq '.returns.swEthHandler.value' "broadcast/08_DeployInitialHandlers.s.sol/$chain_id/run-latest.json" | xargs)
# ion_zapper_addr=$(jq '.returns.ionZapper.value' "broadcast/10_DeployIonZapper.s.sol/$chain_id/run-latest.json" | xargs)

# echo "{
#     \"interestRate\": \"$interest_rate_addr\",
#     \"ionPool\": \"$ionpool_addr\",
#     \"ionZapper\": \"$ion_zapper_addr\",  
#     \"whitelist\": \"$whitelist_addr\", 
#     \"wstEthHandler\": \"$wst_eth_handler_addr\",
#     \"ethXHandler\": \"$eth_x_handler_addr\",
#     \"swEthHandler\": \"$sw_eth_handler_addr\"
# }" > ./deployment-config/DeployedAddresses.json

# bash gen-env.sh 