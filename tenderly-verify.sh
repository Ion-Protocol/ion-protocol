# Verify already deployed contracts in Tenderly 
source .env 

account_slug="ion-protocol"
project_slug="money-market-v1"
RID="349c0360-db87-4329-a34d-b021695b1cae"
chain_id="2" 

# Deployed contracts 
ionpool_addr=$(jq '.returns.ionPool.value' "broadcast/04_DeployIonPool.s.sol/$chain_id/run-latest.json" | xargs)
ion_zapper_addr=$(jq '.returns.ionZapper.value' "broadcast/10_DeployIonZapper.s.sol/$chain_id/run-latest.json" | xargs)
liquidation_addr=$(jq '.returns.liquidation.value' "broadcast/09_DeployLiquidation.s.sol/$chain_id/run-latest.json" | xargs)
yield_oracle_addr=$(jq '.returns.yieldOracle.value' "broadcast/01_DeployYieldOracle.s.sol/$chain_id/run-latest.json" | xargs)
whitelist_addr=$(jq '.returns.whitelist.value' "broadcast/03_DeployWhitelist.s.sol/$chain_id/run-latest.json" | xargs)

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
--verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
--watch \
--etherscan-api-key $TENDERLY_API_KEY \

forge verify-contract $ion_zapper_addr src/periphery/IonZapper.sol:IonZapper \
--compiler-version 0.8.21 \
--verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
--watch \
--etherscan-api-key $TENDERLY_API_KEY \

forge verify-contract $liquidation_addr src/Liquidation.sol:Liquidation \
--compiler-version 0.8.21 \
--verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
--watch \
--etherscan-api-key $TENDERLY_API_KEY \

forge verify-contract $yield_oracle_addr src/YieldOracle.sol:YieldOracle \
--compiler-version 0.8.21 \
--verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
--watch \
--etherscan-api-key $TENDERLY_API_KEY \

forge verify-contract $whitelist_addr src/Whitelist.sol:Whitelist \
--compiler-version 0.8.21 \
--verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
--watch \
--etherscan-api-key $TENDERLY_API_KEY \

forge verify-contract $wst_eth_handler_addr src/flash/handlers/WstEthHandler.sol:WstEthHandler \
--compiler-version 0.8.21 \
--verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
--watch \
--etherscan-api-key $TENDERLY_API_KEY \

forge verify-contract $wst_eth_join_addr src/join/GemJoin.sol:GemJoin \
--compiler-version 0.8.21 \
--verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
--watch \
--etherscan-api-key $TENDERLY_API_KEY \

forge verify-contract $wst_eth_spot src/oracles/spot/WstEthSpotOracle.sol:WstEthSpotOracle \
--compiler-version 0.8.21 \
--verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
--watch \
--etherscan-api-key $TENDERLY_API_KEY \

forge verify-contract $wst_eth_reserve src/oracles/reserve/WstEthReserveOracle.sol:WstEthReserveOracle \
--compiler-version 0.8.21 \
--verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
--watch \
--etherscan-api-key $TENDERLY_API_KEY \

# --num-of-optimizations= \
