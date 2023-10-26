# read and set env variables
export $(grep -v '^#' .env | xargs)

echo "Running fork tests!"

# create csv to store results
touch $UNISWAP_SWETH_FILE_PATH

# run fork test
forge test --match-contract UniswapSwapTester --match-test testSwETHSwapRange

# write fork test to DB
# node offchain/uploadAmmCoaData.cjs

# set up libraries for python analysis
pip3 install pandas plotly python-dotenv

# run python anaylsis file
python3 ./offchain/amm_fork_data_analysis.py