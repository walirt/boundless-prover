# Boundless prover
> 在无Docker环境中运行boundless prover

[English](https://github.com/walirt/boundless-prover/blob/main/README.md) | 中文

## 运行
1. 复制以下命令到控制台，然后根据打印日志输入合适的参数和执行命令
```bash
apt update 
apt install -y curl
curl -L "https://raw.githubusercontent.com/walirt/boundless-prover/refs/heads/main/setup_zh.sh" -o setup.sh
bash setup.sh
```
2. 向市场存入资金
```bash
export RPC_URL=<目标链RPC_URL>
export PRIVATE_KEY=<私钥>
# eth sepolia
source /app/.env.eth-sepolia
# base sepolia
# source /app/.env.base-sepolia
# base mainnet
# source /app/.env.base
boundless account deposit-stake 10
```
3. 测试bento是否正常工作
```bash
RUST_LOG=info bento_cli -c 32
```
4. 对bento进行基准测试，您可以在这里获得`peak_prove_khz`参数的参考值
```bash
export RPC_URL=<目标链RPC_URL>
boundless proving benchmark --request-ids <请求ID>
```
5. 修改broker的配置文件，路径为`/app/broker<N>.toml`，`N`是您的broker编号
6. 运行broker
```bash
supervisorctl start broker:*
```

## 名词解释
1. `bento`，是用于生成证明的所有组件的统称
2. `broker`，负责市场交互，包括竞标任务、锁定任务、向Bento证明集群发出任务请求，以及在链上提交证明完成
3. `bento_cli`，是与`bento`通信的命令行界面
4. `boundless`，是与Boundless市场交互的命令行界面
5. `supervisord`，进程管理服务，在这里用作docker的替代方案
6. `supervisorctl`，是与`supervisord`通信的命令行界面

## 脚本执行流程
1. 安装系统依赖、rust和RISC Zero工具链
2. 安装bento、broker、bento_cli、boundless和其他生成证明所需的二进制文件
3. 生成supervisord配置文件
4. 初始化数据库，启动依赖服务和bento
5. 打印常用命令

## 注意
1. 此脚本会根据您输入的N个GPU ID信息生成N个`gpu_prove_agent`，根据您输入的N个网络信息生成N个`broker`
2. 此脚本不保证您的证明器会获得任务
3. 当前的broker使用默认参数，您需要修改`/app/broker<N>.toml`文件

## 参考
[boundless](https://github.com/boundless-xyz/boundless)  
[boundless文档](https://docs.beboundless.xyz/provers/quick-start)

## 联系我
[![Twitter](https://img.shields.io/twitter/url/https/twitter.com/walirttt.svg?style=social&label=关注%20%40walirttt)](https://twitter.com/walirttt)
