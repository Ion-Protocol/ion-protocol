# cli to select which deployments to run 
# runs the forge script for each solidity script 
# after it's done, moves the deployment config and output to it's directory based on marketId 

#!/bin/bash
source .env

# Required environmental variables
# $RPC_URL
# $PRIVATE_KEY 

echo "Select the Deployment Script:"

options=(
    "01_DeployYieldOracle"
    "02_DeployInterestRateModule"
    "03_DeployWhitelist"
    "04_DeployIonPool"
    "05_DeployInitialReserveAndSpotOracles"
    "06_DeployInitialCollateralsSetUp"
    "07_DeployInitialGemJoins"
    "08_DeployInitialHandlers"
    "09_DeployLiquidation"
    "10_DeployIonZapper"
)

get_chain_id() {
    local rpc_url=$1

    response=$(curl -s "$rpc_url" \
      -X POST \
      -H "Content-Type: application/json" \
      --data '{"method":"eth_chainId","params":[],"id":1,"jsonrpc":"2.0"}')

    chain_id=$(echo $response | jq -r '.result')

    if [ -z "$chain_id" ]; then
        echo "Failed to extract chain ID"
        return 1
    fi

    echo $(( $chain_id ))
}

prompt_for_number() {
    local input_value
    while true; do
        read -p "Enter market_id: " input_value

        # Check if the input is an integer
        if [[ -z "$input_value" ]]; then
            echo -e "Input cannot be empty. Please try again.\n" >&2 # stderr
        elif ! [[ "$input_value" =~ ^-?[0-9]+$ ]]; then
            echo -e "Invalid input. Please enter an integer.\n" >&2 # stderr
        else
            echo $input_value
            break
        fi
    done
}

run_forge_script() {
    script_name=$1
    market_id=$2

    echo "script_name: " $script_name 
    echo "market_id: " $market_id

    echo "" 
    echo "Running: forge script script/deploy/$script_name.s.sol --rpc-url $RPC_URL --private-key <PRIVATE_KEY> --broadcast --slow"
    echo "" 

    forge script script/deploy/$script_name.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --slow
    if [ $? -eq 0 ]; then 
        echo "forge script success" 
    else 
        echo "Error forge script"
        exit 1 
    fi

    config_path="deployment-config/${script_name}.json" 
    config_data=$(cat "$config_path")

    chainId=$(get_chain_id $RPC_URL)
    run_latest_path="broadcast/${script_name}.s.sol/${chainId}/run-latest.json" 
    timestamp=$(jq -r '.timestamp' "$run_latest_path")

    echo "chainId: " $chainId 
    echo "timestamp: " $timestamp
    echo "run_latest_path: " $run_latest_path 
    echo "config_path: " $config_path
    echo "config_data: " $config_data

    if [ -z "$timestamp" ]; then 
        echo "Timestamp not found in $run_latest_path" 
        exit 1
    fi  

    new_dir="deployment/${market_id}/${script_name}/${chainId}"

    echo "new_dir: " $new_dir 

    mkdir -p "$new_dir" # create if directory doesn't exist

    jq --argjson config "$config_data" '. + { "deploymentConfig": $config}' "$run_latest_path" > "${new_dir}/run-${timestamp}.json"
    if [ $? -eq 0 ]; then 
        echo "Transactions saved to: $new_dir" 
    else 
        echo "Error writing broadcast output to deployment directory" 
    fi
}

select opt in "${options[@]}"
do
    if [[ " ${options[*]} " =~ " $opt " ]]; then
        echo "You selected $opt"
        echo ""
        num=$(prompt_for_number)
        echo ""
        run_forge_script $opt $num
        break
    else
        echo "Invalid option $REPLY"
    fi
done
