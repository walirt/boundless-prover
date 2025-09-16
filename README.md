# Boundless prover
> This script helps you to Run boundless prover without docker environment  
> Current version: [v1.0.0](https://github.com/boundless-xyz/boundless/releases/tag/v1.0.0)

English | [中文](https://github.com/walirt/boundless-prover/blob/main/README_zh.md)

## Run
1. Copy the following command to the console and wait for the script to download the dependency and prover binaries, depending on your internet download speed, this usually takes around 25-30 minutes
    ```bash
    apt update 
    apt install -y curl
    curl -L "https://raw.githubusercontent.com/walirt/boundless-prover/refs/heads/main/setup.sh" -o setup.sh
    bash setup.sh
    ```

2. Select the GPU IDs you want to use, separated by commas, for example
![](https://github.com/walirt/boundless-prover/blob/main/1.png?raw=true)
    ```bash
    0   # Use GPU with ID 0
    0,1 # Use GPU with ID 0 and 1
    ```

3. Select the networks you want to join, separated by commas, for example
![](https://github.com/walirt/boundless-prover/blob/main/2.png?raw=true)
    ```bash
    1   # Join the Eth Sepolia testnet
    1,2 # Join the Eth Sepolia and Base Sepolia testnet
    3   # Join the Base mainnet
    ```
    then enter the RPC URL and wallet private key for the chosen network

4. Restart the console or run the following command
    ```bash
    source /root/.cargo/env
    source /root/.bashrc
    ```

5. Deposit funds into the network you want to join ( Deduct <> signs)
    - Eth Sepolia
    ```bash
    export RPC_URL=<ETH_SEPOLIA_RPC_URL>
    export PRIVATE_KEY=<PRIVATE_KEY>
    source /app/.env.eth-sepolia
    boundless account deposit-stake 10
    ```
    - Base Sepolia
    ```bash
    export RPC_URL=<BASE_SEPOLIA_RPC_URL>
    export PRIVATE_KEY=<PRIVATE_KEY>
    source /app/.env.base-sepolia
    boundless account deposit-stake 10
    ```
    - Base mainnet
    ```bash
    export RPC_URL=<BASE_MAINNET_RPC_URL>
    export PRIVATE_KEY=<PRIVATE_KEY>
    source /app/.env.base
    boundless account deposit-stake 10
    ```

6. Test that bento is working properly
    ```bash
    RUST_LOG=info bento_cli -c 32
    ```

7. Benchmarking bento, you can get a reference value for the `peak_prove_khz` parameter here
    ```bash
    export RPC_URL=<TARGET_CHAIN_RPC_URL>
    boundless proving benchmark --request-ids <IDS>
    ```

8. Modify the broker's configuration file, the path is `/app/broker<N>.toml`, `N` is your broker number
    - Eth Sepolia
        - /app/broker1.toml 
    - Base Sepolia
        - /app/broker2.toml 
    - Base mainnet
        - /app/broker3.toml 

9. Run the broker
    ```bash
    supervisorctl start broker:*
    ```

## Basic Commands
### Checking stake balance
```bash
export RPC_URL=<TARGET_CHAIN_RPC_URL>
export PRIVATE_KEY=<KEY>
boundless account stake-balance
```

### Service management  
All of them are independent commands to start , stop or restart a service. Your prover is running through `supervisord` so use `supervisorctl` commands to manage it
- Dependencies:
    ```bash
    supervisorctl start dependencies:*
    supervisorctl stop dependencies:*
    supervisorctl restart dependencies:*
    ```
- Bento:
    ```bash
    supervisorctl start bento:*
    supervisorctl stop bento:*
    supervisorctl restart bento:*
    ```
- Broker:
    ```bash
    supervisorctl start broker:*
    supervisorctl stop broker:*
    supervisorctl restart broker:*
    ```
- Logs:
    ```bash
    supervisorctl tail broker:broker1 # Eth Sepolia
    supervisorctl tail broker:broker2 # Base Sepolia
    supervisorctl tail broker:broker2 # Base mainnet
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
3. The current broker uses the default parameters, you need to modify the `/app/broker<N>.toml` file

## Reference
[boundless](https://github.com/boundless-xyz/boundless)  
[boundless doc](https://docs.beboundless.xyz/provers/quick-start)

## Contact me
[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/walirttt.svg?style=social&label=Follow%20%40walirttt)](https://twitter.com/walirttt)
