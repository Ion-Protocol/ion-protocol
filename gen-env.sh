# generate env variables for webapp 

# Set Chain ID based on deployment route 
source .env
if [ $RPC_URL == "http://localhost:8545" ]; then
    chain_id=31337 
else 
    chain_id=$CHAIN_ID
fi

# Constants 
weth_addr="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
st_eth_addr="0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
wst_eth_addr="0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"
eth_x_addr="0xA35b1B31Ce002FBF2058D22F30f95D405200A15b"
sw_eth_addr="0xf951E335afb289353dc249e82926178EaC7DEd78"

# Deployed contracts 
ionpool_addr=$(jq '.returns.ionPool.value' "broadcast/04_DeployIonPool.s.sol/$chain_id/run-latest.json" | xargs)
ion_zapper_addr=$(jq '.returns.ionZapper.value' "broadcast/10_DeployIonZapper.s.sol/$chain_id/run-latest.json" | xargs)
liquidation_addr=$(jq '.returns.liquidation.value' "broadcast/09_DeployLiquidation.s.sol/$chain_id/run-latest.json" | xargs)
yield_oracle_addr=$(jq '.returns.yieldOracle.value' "broadcast/01_DeployYieldOracle.s.sol/$chain_id/run-latest.json" | xargs)
interest_rate_addr=$(jq '.returns.interestRateModule.value' "broadcast/02_DeployInterestRateModule.s.sol/$chain_id/run-latest.json" | xargs)

wst_eth_handler_addr=$(jq '.returns.wstEthHandler.value' "broadcast/08_DeployInitialHandlers.s.sol/$chain_id/run-latest.json" | xargs)
wst_eth_join_addr=$(jq '.returns.wstEthGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)
wst_eth_spot_addr=$(jq '.returns.wstEthSpotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
wst_eth_reserve=$(jq '.returns.wstEthReserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

eth_x_handler_addr=$(jq '.returns.ethXHandler.value' "broadcast/08_DeployInitialHandlers.s.sol/$chain_id/run-latest.json" | xargs)
eth_x_join_addr=$(jq '.returns.ethXGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)
eth_x_spot_addr=$(jq '.returns.ethXSpotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
eth_x_reserve_addr=$(jq '.returns.ethXReserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

sw_eth_join_addr=$(jq '.returns.swEthGemJoin.value' "broadcast/07_DeployInitialGemJoins.s.sol/$chain_id/run-latest.json" | xargs)
sw_eth_handler_addr=$(jq '.returns.swEthHandler.value' "broadcast/08_DeployInitialHandlers.s.sol/$chain_id/run-latest.json" | xargs)
sw_eth_spot_addr=$(jq '.returns.swEthSpotOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)
sw_eth_reserve_addr=$(jq '.returns.swEthReserveOracle.value' "broadcast/05_DeployInitialReserveAndSpotOracles.s.sol/$chain_id/run-latest.json" | xargs)

echo "
ionPool: \"$ionpool_addr\",
ionZapper: \"$ion_zapper_addr\",
liquidation: \"$liquidation_addr\",
yieldOracle: \"$yield_oracle_addr\",
interestRate: \"$interest_rate_addr\",

wstEthHandler: \"$wst_eth_handler_addr\",
wstEthGemJoin: \"$wst_eth_join_addr\",
wstEthSpotOracle: \"$wst_eth_spot_addr\",
wstEthReserveOracle: \"$wst_eth_reserve\",

swEthHandler: \"$sw_eth_handler_addr\",
swEthGemJoin: \"$sw_eth_join_addr\",
swEthSpotOracle: \"$sw_eth_spot_addr\",
swEthReserveOracle: \"$sw_eth_reserve_addr\",

ethXHandler: \"$eth_x_handler_addr\",
ethXGemJoin: \"$eth_x_join_addr\",
ethXSpotOracle: \"$eth_x_spot_addr\",
ethXReserveOracle: \"$eth_x_reserve_addr\",

wEth: \"$weth_addr\",

wstEth: \"$wst_eth_addr\",
stEth: \"$st_eth_addr\",
ethX: \"$eth_x_addr\",
swEth: \"$sw_eth_addr\",
" > ./deployment-config/webapp.env.sample
