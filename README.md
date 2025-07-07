# Boundless prover
> Run boundless prover without docker environment

English | [中文](https://github.com/walirt/boundless-prover/blob/main/README_zh.md)

## Run
1. Copy the following commands to the console, then enter the appropriate parameters and execute the commands according to the print logs
```bash
apt update 
apt install -y curl
curl -L "https://raw.githubusercontent.com/walirt/boundless-prover/refs/heads/main/setup.sh" -o setup.sh
bash setup.sh
```
2. Depositing funds to the market
```bash
export RPC_URL=<TARGET_CHAIN_RPC_URL>
export PRIVATE_KEY=<PRIVATE_KEY>
# eth sepolia
source /app/.env.eth-sepolia
# base sepolia
# source /app/.env.base-sepolia
# base mainnet
# source /app/.env.base
boundless account deposit-stake 10
```
3. Test that bento is working properly
```bash
RUST_LOG=info bento_cli -c 32
```
4. Benchmarking bento, you can get a reference value for the `peak_prove_khz` parameter here
```bash
export RPC_URL=<TARGET_CHAIN_RPC_URL>
boundless proving benchmark --request-ids <IDS>
```
5. Modify the broker's configuration file, the path is `/app/broker<N>.toml`, `N` is your broker number.
6. Run the broker
```bash
supervisorctl start broker:*
```

## Explanation of nouns
1. `bento`, is a collective term for all the components used to generate proofs
2. `broker`, is responsible for market interactions including bidding on jobs, locking them, issuing job requests to the Bento proving cluster, and submitting proof fulfillments onchain
3. `bento_cli`, is command-line interface for communicating with `bento`
4. `boundless`, is command-line interface for interacting with the Boundless Market
5. `supervisord`, process management service, used here as an alternative to docker
6. `supervisorctl`, is command-line interface for communicating with `supervisord`

## Script execution flow
1. Installation of system dependencies, rust and RISC Zero toolchain
2. Install bento, broker, bento_cli, boundless and other binaries needed to generate the proofs
4. Generate supervisord configuration file
5. Initialize the database, start dependent services and bento
6. Printing common commands

## Note
1. The script will generate N `gpu_prove_agent` based on the N GPU ID information you enter and N `broker` based on the N network information you enter
2. This script does not guarantee that your prover will get the task
3. The current broker uses the default parameters, you need to modify the /app/broker<N>.toml file

## Reference
[boundless](https://github.com/boundless-xyz/boundless)  
[boundless doc](https://docs.beboundless.xyz/provers/quick-start)

## Contact me
[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/walirttt.svg?style=social&label=Follow%20%40walirttt)](https://twitter.com/walirttt)
