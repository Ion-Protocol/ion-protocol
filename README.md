## Ion Protocol
TODO: [Overview] 

## User Docs

`docs.ionprotocol.io`

## Technical Docs

## Usage

### Installing Dependencies 

Install Bun 
```shell
$ curl -fsSL https://bun.sh/install | bash 
```

Run Bun install for javascript dependencies
```shell
$ bun install
```

Install jq 
```shell
$ brew install jq 
```

### Environmental Variables 

Copy .env.example to .env and add environmental variables. 

```
MAINNET_RPC_URL=https://mainnet.infura.io/v3/
MAINNET_ARCHIVE_RPC_URL=
MAINNET_ETHERSCAN_URL=https://api.etherscan.io/api
ETHERSCAN_API_KEY=
```

### Test

1. The test suite includes fork tests that require foundry ffi. 
2. Add RPC_URLs to the .env and run forge test with the --ffi flag. 
```shell
$ forge test --ffi 
```
### Testnet Setup
TODO: document testnet setup with env 

### Format

```shell
$ forge fmt
```
