rm -rf coverage
forge coverage --report lcov

delete=false

while read -r line; do
    if [[ $line == SF* ]]; then
        path=$(echo "$line" | cut -d':' -f2)
        if [[ $path == test* || $path == script* || $path == src/libraries/uniswap* ]]; then
            delete=true
            continue
        fi
    fi

    if [[ $delete == true && $line == end_of_record* ]]; then
        delete=false
    fi

    if [[ $delete == false ]]; then
        echo "$line" >>lcov.info.pruned
    fi

done <lcov.info
mv lcov.info.pruned lcov.info

genhtml --branch-coverage --output "coverage" lcov.info
open coverage/index.html
