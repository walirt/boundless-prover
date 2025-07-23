# Boundless prover
> 此脚本帮助您在无Docker环境中运行boundless prover  
> 当前版本：[v0.13.0](https://github.com/boundless-xyz/boundless/releases/tag/v0.13.0)

[English](https://github.com/walirt/boundless-prover/blob/main/README.md) | 中文

## 运行
1. 复制以下命令到控制台，等待脚本下载依赖和prover二进制文件，根据您的网络下载速度，通常需要25-30分钟
    ```bash
    apt update 
    apt install -y curl
    curl -L "https://raw.githubusercontent.com/walirt/boundless-prover/refs/heads/main/setup_zh.sh" -o setup.sh
    bash setup.sh
    ```

2. 选择您要使用的GPU ID，用英文逗号分隔，例如
![](https://github.com/walirt/boundless-prover/blob/main/1.png?raw=true)
    ```bash
    0   # 使用ID为0的GPU
    0,1 # 使用ID为0和1的GPU
    ```

3. 选择您要加入的网络，用英文逗号分隔，例如
![](https://github.com/walirt/boundless-prover/blob/main/2.png?raw=true)
    ```bash
    1   # 加入Eth Sepolia测试网
    1,2 # 加入Eth Sepolia和Base Sepolia测试网
    3   # 加入Base主网
    ```
    然后为所选网络输入RPC URL和钱包私钥

4. 重启控制台或运行以下命令
    ```bash
    source /root/.cargo/env
    source /root/.bashrc
    ```

5. 向您要加入的网络存入资金（去掉尖括号）
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
    - Base主网
    ```bash
    export RPC_URL=<BASE_MAINNET_RPC_URL>
    export PRIVATE_KEY=<PRIVATE_KEY>
    source /app/.env.base
    boundless account deposit-stake 10
    ```

6. 测试bento是否正常工作
    ```bash
    RUST_LOG=info bento_cli -c 32
    ```

7. 对bento进行基准测试，您可以在获得`peak_prove_khz`参数的参考值
    ```bash
    export RPC_URL=<目标链RPC_URL>
    boundless proving benchmark --request-ids <请求ID>
    ```

8. 修改broker的配置文件，路径为`/app/broker<N>.toml`，`N`是您的broker编号
    - Eth Sepolia
        - /app/broker1.toml 
    - Base Sepolia
        - /app/broker2.toml 
    - Base主网
        - /app/broker3.toml 

9. 运行broker
    ```bash
    supervisorctl start broker:*
    ```

## 基本命令
### 检查质押余额
```bash
export RPC_URL=<目标链RPC_URL>
export PRIVATE_KEY=<私钥>
boundless account stake-balance
```

### 服务管理
这些都是独立的命令，用于启动、停止或重启服务。您的证明器通过`supervisord`运行，所以使用`supervisorctl`命令来管理它
- 依赖服务:
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
- 日志:
    ```bash
    supervisorctl tail broker:broker1 # Eth Sepolia
    supervisorctl tail broker:broker2 # Base Sepolia
    supervisorctl tail broker:broker3 # Base主网
    ```

## 名词解释
1. `bento`：用于生成证明的所有组件的统称
2. `broker`：负责市场交互，包括竞标任务、锁定任务、向Bento证明集群发出任务请求，以及在链上提交证明完成
3. `bento_cli`：与`bento`通信的命令行界面
4. `boundless`：与Boundless市场交互的命令行界面
5. `supervisord`：进程管理服务，这里用作docker的替代方案
6. `supervisorctl`：与`supervisord`通信的命令行界面

## 脚本执行流程
1. 安装系统依赖、rust和RISC Zero工具链
2. 安装bento、broker、bento_cli、boundless和其他生成证明所需的二进制文件
3. 生成supervisord配置文件
4. 初始化数据库，启动依赖服务和bento
5. 打印常用命令

## 注意
1. 脚本会根据您输入的N个GPU ID信息生成N个`gpu_prove_agent`，根据您输入的N个网络信息生成N个`broker`
2. 脚本不保证您的证明器会获得任务
3. 当前的broker使用默认参数，您需要修改`/app/broker<N>.toml`文件

## 参考
[boundless](https://github.com/boundless-xyz/boundless)  
[boundless文档](https://docs.beboundless.xyz/provers/quick-start)

## 联系我
[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/walirttt.svg?style=social&label=关注%20%40walirttt)](https://twitter.com/walirttt)
