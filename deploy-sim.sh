# Run
# 1. Set up testnet
#    - via `anvil --fork-url $MAINNET_ARCHIVE_RPC_URL --chain-id 31337` or Tenderly Devnet.
# 2. Set the env variables.
# 3. Run `bash node.sh`
# 4. forge script script/__TestFlashLeverage.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY

source .env

# Env Variables
echo "===== Current Env Variables ====="
echo "ETH_FROM: " $ETH_FROM
echo "DEPLOY_SIM_CHAIN: " $DEPLOY_SIM_CHAIN
# Set Chain ID based on deployment route
if [ $DEPLOY_SIM_CHAIN == 'anvil' ]; then
    chain_name='anvil'
    chain_id=31337
    # Fund the ETH_FROM address with gas token (for anvil or tenderly)
    echo "Fund Wallet..."
    curl http://localhost:8545 -X POST -H "Content-Type: application/json" --data "{\"method\":\"anvil_setBalance\",\"params\":[\"$ETH_FROM\", \"0x021e19e0c9bab2400000\"],\"id\":1,\"jsonrpc\":\"2.0\"}"
    echo ""
else
    chain_name='tenderly'
    chain_id=$TENDERLY_CHAIN_ID
    private_key=$PRIVATE_KEY
fi
echo ""
echo "===== Env Variables in Use ======"
echo -e "chain_name: $chain_name"
echo -e "chain_id: $chain_id"
echo ""
echo "===== Simulate Deployment ======="

# Deploy YieldOracle
echo "DEPLOYING YIELD ORACLE..."
# bun run 01_DeployYieldOracle:deployment:configure
# bun run 01_DeployYieldOracle:deployment:deploy:$chain_name --broadcast
bun run 01a_DeployYieldOracleNull:deployment:deploy:$chain_name --broadcast

# Copy YieldOracle address from latest deployment and dump it into InterestRate deployment config
# yield_oracle_addr=$(jq '.returns.yieldOracle.value' "broadcast/01_DeployYieldOracle.s.sol/$chain_id/run-latest.json" | xargs)
yield_oracle_addr=$(jq '.returns.yieldOracle.value' "broadcast/01a_DeployYieldOracleNull.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg address "$yield_oracle_addr" '. + { "yieldOracleAddress": $address }' deployment-config/02_DeployInterestRateModule.json >temp.json && mv temp.json deployment-config/02_DeployInterestRateModule.json

# Deploy InterestRate module and whitelist
echo "DEPLOYING INTEREST RATE MODULE..."
bun run 02_DeployInterestRateModule:deployment:deploy:$chain_name --broadcast

echo "DEPLOYING WHITELIST"
bun run 03_DeployWhitelist:deployment:deploy:$chain_name --broadcast

# Copy InterestRate and whitelist addresses from latest deployment and dump them into IonPool deployment config
interest_rate_addr=$(jq '.returns.interestRateModule.value' "broadcast/02_DeployInterestRateModule.s.sol/$chain_id/run-latest.json" | xargs)
whitelist_addr=$(jq '.returns.whitelist.value' "broadcast/03_DeployWhitelist.s.sol/$chain_id/run-latest.json" | xargs)
jq --arg interest_rate "$interest_rate_addr" --arg whitelist "$whitelist_addr" '. + { "interestRateModule": $interest_rate, whitelist: $whitelist }' deployment-config/04_DeployIonPool.json >temp.json && mv temp.json deployment-config/04_DeployIonPool.json

# Deploy IonPool!
echo "DEPLOYING ION POOL..."
bun run 04_DeployIonPool:deployment:deploy:$chain_name --broadcast

# Deploy Oracles
echo "DEPLOYING ORACLES..."
bun run 05_DeployInitialReserveAndSpotOracles:deployment:deploy:$chain_name --broadcast

# Copy IonPool address from latest deployment and dump it into initial setup config
ionpool_addr=$(jq '.returns.ionPool.value' "broadcast/04_DeployIonPool.s.sol/$chain_id/run-latest.json" | xargs)
spot_oracle=$(jq '.returns.spotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg ionpool_addr "$ionpool_addr" --arg spot_oracle "$spot_oracle" '. + { "ionPool": $ionpool_addr, "spotOracle": $spot_oracle }' deployment-config/06_SetupCollateral.json >temp.json && mv temp.json deployment-config/06_SetupCollateral.json

# Setup initial collaterals
bun run 06_SetupCollateral:deployment:deploy:$chain_name --broadcast

jq --arg ionpool_addr "$ionpool_addr" '. + { "ionPool": $ionpool_addr }' deployment-config/07_DeployGemJoin.json >temp.json && mv temp.json deployment-config/07_DeployGemJoin.json

# Deploy GemJoins
bun run 07_DeployGemJoin:deployment:deploy:$chain_name --broadcast

gem_join_addr=$(jq '.returns.gemJoin.value' "broadcast/07_DeployGemJoin.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg ionpool_addr "$ionpool_addr" --arg gem_join "$gem_join_addr" --arg whitelist "$whitelist_addr" '. + { "ionPool": $ionpool_addr, "gemJoin": $gem_join, whitelist: $whitelist }' deployment-config/08_DeployHandlers.json >temp.json && mv temp.json deployment-config/08_DeployHandlers.json

# Deploy Handlers
bun run 08_DeployHandlers:deployment:deploy:$chain_name --broadcast

# Deploy Liquidation
echo "DEPLOYING LIQUIDATION..."
reserve_oracle=$(jq '.returns.reserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

jq --arg ionpool_addr "$ionpool_addr" \
    --arg reserve_oracle "$reserve_oracle" \
    '. + { "ionPool": $ionpool_addr, "reserveOracle": $reserve_oracle }' deployment-config/09_DeployLiquidation.json >temp.json && mv temp.json deployment-config/09_DeployLiquidation.json

bun run 09_DeployLiquidation:deployment:deploy:$chain_name --broadcast

# AdminTransfer and tests

# write all the deployed addresses to json
weeth_handler_addr=$(jq '.returns.handler.value' "broadcast/08_DeployHandlers.s.sol/$chain_id/run-latest.json" | xargs)
liquidation=$(jq '.returns.liquidation.value' "broadcast/09_DeployLiquidation.s.sol/$chain_id/run-latest.json" | xargs)

echo "{
    \"yieldOracle\": \"$yield_oracle_addr\",
    \"interestRate\": \"$interest_rate_addr\",
    \"whitelist\": \"$whitelist_addr\",
    \"ionPool\": \"$ionpool_addr\",
    \"gemJoin\": \"$gem_join_addr\",
    \"weEthReserveOracle\": \"$reserve_oracle\",
    \"weEthSpotOracle\": \"$spot_oracle\",
    \"weEthHandler\": \"$weeth_handler_addr\",
    \"liquidation\": \"$liquidation\"
}" >./deployment-config/DeployedAddresses.json

# bash gen-env.sh
