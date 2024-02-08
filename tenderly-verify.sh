source .env 

account_slug=$TENDERLY_ACCOUNT
project_slug=$TENDERLY_PROJECT
RID=$TENDERLY_RID
chain_id=$TENDERLY_CHAIN_ID 

# Function to verify contract
verify_contract() {
    local addr=$1
    local contract_path=$2
    local contract_name=$3

    forge verify-contract $addr $contract_path:$contract_name \
    --compiler-version 0.8.21 \
    --verifier-url https://api.tenderly.co/api/v1/account/$account_slug/project/$project_slug/etherscan/verify/testnet/$RID \
    --watch \
    --etherscan-api-key $TENDERLY_API_KEY
}

# Array of file, key, path 
declare -a contracts=(
    "01_DeployYieldOracle.s.sol yieldOracle src/YieldOracle.sol"
    "02_DeployInterestRateModule.s.sol interestRateModule src/InterestRate.sol"
    "03_DeployWhitelist.s.sol whitelist src/Whitelist.sol"

    "04_DeployIonPool.s.sol ionPoolImpl src/IonPool.sol"
    "04_DeployIonPool.s.sol ionPool src/admin/TransparentUpgradeableProxy.sol"

    "05_DeployInitialReserveAndSpotOracles.s.sol wstEthSpotOracle src/oracles/spot/WstEthSpotOracle.sol"
    "05_DeployInitialReserveAndSpotOracles.s.sol ethXSpotOracle src/oracles/spot/EthXSpotOracle.sol"
    "05_DeployInitialReserveAndSpotOracles.s.sol swEthSpotOracle src/oracles/spot/SwEthSpotOracle.sol"
    
    "05_DeployInitialReserveAndSpotOracles.s.sol wstEthReserveOracle src/oracles/reserve/WstEthReserveOracle.sol"
    "05_DeployInitialReserveAndSpotOracles.s.sol ethXReserveOracle src/oracles/reserve/EthXReserveOracle.sol"
    "05_DeployInitialReserveAndSpotOracles.s.sol swEthReserveOracle src/oracles/reserve/SwEthReserveOracle.sol"

    "07_DeployInitialGemJoins.s.sol wstEthGemJoin src/join/GemJoin.sol"
    "07_DeployInitialGemJoins.s.sol ethXGemJoin src/join/GemJoin.sol"
    "07_DeployInitialGemJoins.s.sol swEthGemJoin src/join/GemJoin.sol"

    "08_DeployInitialHandlers.s.sol wstEthHandler src/flash/handlers/WstEthHandler.sol"
    "08_DeployInitialHandlers.s.sol ethXHandler src/flash/handlers/EthXHandler.sol"
    "08_DeployInitialHandlers.s.sol swEthHandler src/flash/handlers/SwEthHandler.sol"

    "09_DeployLiquidation.s.sol liquidation src/Liquidation.sol"
    "10_DeployIonZapper.s.sol ionZapper src/periphery/IonZapper.sol"
)

# Loop through contracts and verify
for contract_info in "${contracts[@]}"; do
    read -r file key path contract <<< "$contract_info"
    addr=$(jq ".returns.${key}.value" "broadcast/$file/$chain_id/run-latest.json" | xargs)
    contract=$(basename "$path" .sol) # get contract name from path

    echo "---"
    echo "addr" $addr 
    echo "path" $path 
    echo "contract" $contract 
    echo "---"

    verify_contract $addr $path $contract
done
