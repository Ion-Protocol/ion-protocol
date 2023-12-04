# Verify already deployed contracts in Tenderly 
source .env 

account_slug="ion-protocol"
project_slug="money-market-v1"
chain_id="1" 

# Deployed contracts 
ionpool_addr=$(jq '.returns.ionPool.value' "broadcast/04_DeployIonPool.s.sol/$chain_id/run-latest.json" | xargs)
ion_zapper_addr=$(jq '.returns.ionZapper.value' "broadcast/10_DeployIonZapper.s.sol/$chain_id/run-latest.json" | xargs)
liquidation_addr=$(jq '.returns.liquidation.value' "broadcast/09_DeployLiquidation.s.sol/$chain_id/run-latest.json" | xargs)
yield_oracle_addr=$(jq '.returns.yieldOracle.value' "broadcast/01_DeployYieldOracle.s.sol/$chain_id/run-latest.json" | xargs)

wst_eth_handler_addr=$(jq '.returns.wstEthHandler.value' "broadcast/08_DeployInitialHandlers.s.sol/$chain_id/run-latest.json" | xargs)
wst_eth_join_addr=$(jq '.returns.wstEthGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)
wst_eth_spot=$(jq '.returns.wstEthSpotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
wst_eth_reserve=$(jq '.returns.wstEthReserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

eth_x_handler_addr=$(jq '.returns.ethXHandler.value' "broadcast/08_DeployInitialHandlers.s.sol/$chain_id/run-latest.json" | xargs)
eth_x_join_addr=$(jq '.returns.ethXGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)
eth_x_spot_addr=$(jq '.returns.ethXSpotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
eth_x_reserve_addr=$(jq '.returns.ethXReserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

sw_eth_join_addr=$(jq '.returns.swEthGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)
sw_eth_handler_addr=$(jq '.returns.swEthHandler.value' "broadcast/08_DeployInitialHandlers.s.sol/$chain_id/run-latest.json" | xargs)
sw_eth_spot_addr=$(jq '.returns.swEthSpotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
sw_eth_reserve_addr=$(jq '.returns.swEthReserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)


forge verify-contract $ionpool_addr src/IonPool.sol:IonPool \
--compiler-version 0.8.21 \
--verifier-url "https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/network/$chain_id/public" \
--watch \
--etherscan-api-key $TENDERLY_API_KEY

# --num-of-optimizations= \
