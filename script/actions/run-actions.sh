#!/bin/bash
source .env

# 1. Test the script against a fork 
# 2. Run the script and send transaction to Safe API
# 3. After execution, validate the post-execution state of the network. 

# Function to parse command line arguments
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --tc) contract_name="$2"; shift ;;
            --script) script_name="$2"; shift ;;
            --mode) mode="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; exit 1 ;;
        esac
        shift
    done
}

# Function to run a Forge script
run_forge_script() {
    script_path=$1
    target_contract=$2
    rpc_url=$3
    sender=$4
    ffi_flag=$5
    echo ""
    echo "script_path: " $script_path 
    echo "target_contract: " $target_contract
    # Uncomment below when ready to execute
    if [[ $mode == "test" ]]; then 
        echo "Running: forge script $script_path --tc $target_contract --sig 'run(bool)()' false --fork-url $rpc_url --sender $sender $ffi_flag"
        forge script $script_path --tc $target_contract --sig "run(bool)()" false --fork-url $rpc_url --sender $sender $ffi_flag
    elif [[ $mode == "prod" ]]; then 
        echo "Running: forge script $script_path --tc $target_contract --sig 'run(bool)()' true --fork-url $rpc_url --sender $sender $ffi_flag"
        forge script $script_path --tc $target_contract --sig "run(bool)()" true --fork-url $rpc_url --sender $sender $ffi_flag
    elif [[ $mode == "validate" ]]; then 
        echo "Validate mode selected" 
    else 
        echo "Invalid mode specified" 
        exit 1 
    fi 
}

prompt_for_mode() {
    while true; do
        read -p "Enter mode (test/prod/validate): " input_mode
        case $input_mode in
            test|prod|validate)
                echo $input_mode  # stdout
                break
                ;;
            *)
                echo -e "Invalid input. Please enter 'test', 'prod', or 'validate'.\n" >&2
                ;;
        esac
    done
}

prompt_for_text() {
    local variable_name=$1 
    local input_value 
    while true; do 
        read -p "Enter $variable_name: " input_value
        if [[ -z "$input_value" ]]; then
            echo -e "Input cannot be empty. Please try again.\n" >&2 #stderr 
        else
            echo $input_value
            break
        fi
    done
}

# Function to handle the workflow
handle_workflow() {

    echo "RPC_URL="$RPC_URL
    echo "ETH_FROM="$ETH_FROM
    echo "" 

    # prompt if any of the arguments are not specified 
    if [[ -z "$script_name" ]]; then 
        script_name=$(prompt_for_text "Script Name") 
    fi 
    echo "" 
    if [[ -z "$contract_name" ]]; then 
        contract_name=$(prompt_for_text "Contract Name")
    fi
    echo ""
    if [[ -z "$mode" ]]; then 
        mode=$(prompt_for_mode)
    fi
    echo ""

    script_path="script/actions/${script_name}.s.sol"
    target_contract="${contract}"


    echo "script_name" $script_name
    echo "contract_name" $contract_name
    echo "mode" $mode

    if [[ $mode == "test" ]]; then
        run_forge_script "$script_path" "$contract_name" "$RPC_URL" "$ETH_FROM" "--ffi" 
    elif [[ $mode == "prod" ]]; then
        run_forge_script "$script_path" "$contract_name" "$RPC_URL" "$ETH_FROM" "--ffi"
        validate_class="Validate${cap_script_name}"
        run_forge_script "$script_path" "$validate_class" "$RPC_URL" "$ETH_FROM" "--ffi"
        echo "resulting state on mainnet successfully validated"
    elif [[ $mode == "validate" ]]; then 
        echo "Validate mode selected" 
    else 
        echo "Invalid mode specified."
        exit 1
    fi
}

# Main execution
parse_arguments "$@"
handle_workflow

