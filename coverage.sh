rm -rf coverage
rm -f lcov.info
forge coverage --report lcov

delete=false

while read -r line; do
    if [[ $line == TN* ]]; then
        read -r line
        if [[ $line == SF* ]]; then
            path=$(echo "$line" | cut -d':' -f2)
            if [[ $path == test* || $path == script* || $path == src/libraries/uniswap* ]]; then
                delete=true
                continue
            fi
        fi
    fi

    if [[ $delete == false ]]; then
        if [[ $line == SF* ]]; then
            echo "TN:" >>lcov.info.pruned
        fi
        echo "$line" >>lcov.info.pruned
    fi

    if [[ $delete == true && $line == end_of_record* ]]; then
        delete=false
    fi

done <lcov.info
mv lcov.info.pruned lcov.info

genhtml --branch-coverage --output "coverage" lcov.info
open coverage/index.html
