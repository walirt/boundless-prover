#!/bin/bash

SILENT_MODE=false
SKIP_CLI_TOOLS=false
while getopts "sc" opt; do
    case $opt in
        s)
            SILENT_MODE=true
            echo "正在使用静默模式运行，使用默认值..."
            ;;
        c)
            SKIP_CLI_TOOLS=true
            echo "跳过CLI工具安装..."
            ;;
        \?)
            echo "无效选项: -$OPTARG" >&2
            echo "用法: $0 [-s] [-c]"
            echo "  -s: 静默模式（使用默认值，无需输入提示）"
            echo "  -c: 跳过CLI工具安装"
            exit 1
            ;;
    esac
done

apt update
apt install -y curl nvtop git supervisor build-essential pkg-config libssl-dev python3-dev
echo

echo "-----正在安装rust-----"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
echo

echo "-----正在安装rzup和RISC Zero工具链-----"
curl -L https://risczero.com/install | bash
source $HOME/.bashrc
/root/.risc0/bin/rzup install
/root/.risc0/bin/rzup install risc0-groth16
echo

echo "-----正在安装bento组件-----"
apt install -y redis postgresql-16 adduser libfontconfig1 musl

wget https://dl.min.io/server/minio/release/linux-amd64/archive/minio_20250613113347.0.0_amd64.deb -O minio.deb
dpkg -i minio.deb

curl -L "https://zzno.de/boundless/grafana-enterprise_11.0.0_amd64.deb" -o grafana-enterprise_11.0.0_amd64.deb
dpkg -i grafana-enterprise_11.0.0_amd64.deb
echo

echo "-----正在下载Prover二进制文件-----"
mkdir /app

curl -L "https://zzno.de/boundless/v1.0.0/broker" -o /app/broker
curl -L "https://zzno.de/boundless/v1.0.0/broker-stress" -o /app/broker-stress
curl -L "https://zzno.de/boundless/v1.0.0/bento-agent-v1_0_1-cuda12_8" -o /app/agent
curl -L "https://zzno.de/boundless/v1.0.0/bento-rest-api" -o /app/rest_api
curl -L "https://zzno.de/boundless/v1.0.0/bento-cli" -o /root/.cargo/bin/bento_cli

chmod +x /app/agent
chmod +x /app/broker
chmod +x /app/broker-stress
chmod +x /app/rest_api
chmod +x /root/.cargo/bin/bento_cli

echo "-----正在验证/app文件sha256sum-----"
declare -A FILES_SHA256
FILES_SHA256["/app/broker"]="216a792c4bb1444a0ce7a447ea2cad0b24e660601baa49057f77b37ac9f4ad74"
FILES_SHA256["/app/broker-stress"]="024d916463d8f24fb9d12857b6f1dbdc016f972e8d8b82434804e077e0fe6231"
FILES_SHA256["/app/agent"]="3be0a008af2ae2a9d5cfacbfbb3f75d4a4fd70b82152ae3e832b500ad468f5a0"
FILES_SHA256["/app/rest_api"]="02a0c87b3bfc1fd738d6714ee24fb32fbcb7887bfe46321c3eed2061c581a87a"
FILES_SHA256["/root/.cargo/bin/bento_cli"]="7af2fe49f75acf95e06476e55e6a91343c238b0cf5696d1cae80be54fcc17b45"

INTEGRITY_PASS=true

for file in "${!FILES_SHA256[@]}"; do
    if [ ! -f "$file" ]; then
        echo "文件缺失: $file"
        INTEGRITY_PASS=false
        continue
    fi
    actual_sum=$(sha256sum "$file" | awk '{print $1}')
    expected_sum="${FILES_SHA256[$file]}"
    if [ "$actual_sum" != "$expected_sum" ]; then
        echo "文件完整性检查失败: $file"
        echo "  期望值: $expected_sum"
        echo "  实际值: $actual_sum"
        INTEGRITY_PASS=false
    else
        echo "文件完整性检查通过: $file"
    fi
done

if [ "$INTEGRITY_PASS" = false ]; then
    echo "部分文件sha256sum检查失败，请验证文件完整性后重试"
    exit 1
else
    echo "所有文件通过sha256sum完整性检查"
fi
echo

echo "-----正在复制配置文件-----"
git clone https://github.com/boundless-xyz/boundless.git
cd boundless
git checkout v1.0.0
if [ "$SKIP_CLI_TOOLS" = false ]; then
    git submodule update --init --recursive
    cargo install --path crates/boundless-cli --locked boundless-cli
fi
cp -rf dockerfiles/grafana/* /etc/grafana/provisioning/
cp .env.base /app/.env.base
cp .env.base-sepolia /app/.env.base-sepolia
cp .env.eth-sepolia /app/.env.eth-sepolia
echo

echo "-----正在生成supervisord配置文件-----"
nvidia-smi -L

if [ "$SILENT_MODE" = true ]; then
    GPU_IDS=$(nvidia-smi --query-gpu=index --format=csv,noheader | tr '\n' ',' | sed 's/,$//')
    echo "使用所有可用GPU: $GPU_IDS"
else
    read -p "请根据打印的GPU信息输入您需要运行的GPU ID（例如 0,1 ，默认全部）: " GPU_IDS
    if [ -z "$GPU_IDS" ]; then
        GPU_IDS=$(nvidia-smi --query-gpu=index --format=csv,noheader | tr '\n' ',' | sed 's/,$//')
    fi
fi

gpu_info=$(nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader)

MIN_SEGMENT_SIZE=22

while IFS=',' read -r index name memory; do
    if ! echo "$GPU_IDS" | grep -q "$index"; then
        continue
    fi

    memory_gb=$(echo "$memory" | tr -d ' MiB' | awk '{printf "%.2f", $1/1024}')
    
    if (( $(awk -v mem="$memory_gb" 'BEGIN{print (mem<16)?1:0}') )); then
        segment_size=19
    elif (( $(awk -v mem="$memory_gb" 'BEGIN{print (mem<20)?1:0}') )); then
        segment_size=20
    elif (( $(awk -v mem="$memory_gb" 'BEGIN{print (mem<40)?1:0}') )); then
        segment_size=21
    else
        segment_size=22
    fi
    
    if [ "$segment_size" -lt "$MIN_SEGMENT_SIZE" ]; then
        MIN_SEGMENT_SIZE=$segment_size
    fi
done <<< "$gpu_info"

echo "根据GPU显存信息，最小SEGMENT_SIZE为：$MIN_SEGMENT_SIZE"

declare -A NETWORK_NAMES
NETWORK_NAMES["1"]="Eth Sepolia"
NETWORK_NAMES["2"]="Base Sepolia"
NETWORK_NAMES["3"]="Base Mainnet"
declare -A NETWORK_ENVS_FILE
NETWORK_ENVS_FILE["1"]="/app/.env.eth-sepolia"
NETWORK_ENVS_FILE["2"]="/app/.env.base-sepolia"
NETWORK_ENVS_FILE["3"]="/app/.env.base"

if [ "$SILENT_MODE" = false ]; then
    for id in $(for key in "${!NETWORK_NAMES[@]}"; do echo "$key"; done | sort -n); do
        echo "$id) ${NETWORK_NAMES[$id]}"
    done
fi

if [ "$SILENT_MODE" = true ]; then
    NETWORK_IDS="3"
    echo "使用默认网络: $NETWORK_IDS (Base Mainnet)"
else
    read -p "请输入您需要运行的网络（例如 1,2,3 ，默认 3）: " NETWORK_IDS
    NETWORK_IDS=${NETWORK_IDS:-3}
fi

IFS=',' read -ra NET_IDS <<< "$NETWORK_IDS"
declare -A NETWORK_RPC
declare -A NETWORK_PRIVKEY

declare -A DEFAULT_RPC
DEFAULT_RPC["1"]="https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY"
DEFAULT_RPC["2"]="https://base-sepolia.g.alchemy.com/v2/YOUR_API_KEY"
DEFAULT_RPC["3"]="https://base-mainnet.g.alchemy.com/v2/YOUR_API_KEY"

DEFAULT_PRIVKEY="0x0000000000000000000000000000000000000000000000000000000000000000"

for NET_ID in "${NET_IDS[@]}"; do
    NET_ID_TRIM=$(echo "$NET_ID" | xargs)
    NETWORK_NAME="${NETWORK_NAMES[$NET_ID_TRIM]}"
    
    if [ "$SILENT_MODE" = true ]; then
        rpc="${DEFAULT_RPC[$NET_ID_TRIM]}"
        privkey="$DEFAULT_PRIVKEY"
        echo "使用${NETWORK_NAME}的默认RPC: $rpc"
        echo "使用${NETWORK_NAME}的默认私钥: $privkey"
        echo "警告：请在启动服务前更新配置文件中的RPC URL和私钥！"
    else
        read -p "请输入${NETWORK_NAME}的RPC地址: " rpc
        read -p "请输入${NETWORK_NAME}的私钥: " privkey
    fi
    
    NETWORK_RPC["$NET_ID_TRIM"]="$rpc"
    NETWORK_PRIVKEY["$NET_ID_TRIM"]="$privkey"
done

POVW_LOG_ID=""
read -p "请输入POVW Log ID: " POVW_LOG_ID

GPU_IDS_ARRAY=()
IFS=',' read -ra GPU_IDS_ARRAY <<< "$GPU_IDS"
GPU_AGENT_CONFIGS=""
for idx in "${!GPU_IDS_ARRAY[@]}"; do
    GPU_ID_TRIM=$(echo "${GPU_IDS_ARRAY[$idx]}" | xargs)
    GPU_AGENT_CONFIGS+="
[program:gpu_prove_agent${idx}]
command=/app/agent -t prove --redis-ttl 57600
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/gpu_prove_agent${idx}.log
redirect_stderr=true
environment=DATABASE_URL=\"postgresql://worker:password@localhost:5432/taskdb\",REDIS_URL=\"redis://localhost:6379\",S3_URL=\"http://localhost:9000\",S3_BUCKET=\"workflow\",S3_ACCESS_KEY=\"admin\",S3_SECRET_KEY=\"password\",RUST_LOG=\"info\",RUST_BACKTRACE=\"1\",CUDA_VISIBLE_DEVICES=\"${GPU_ID_TRIM}\",POVW_LOG_ID=\"${POVW_LOG_ID}\"
"
done

BROKER_CONFIGS=""
for NET_ID in "${NET_IDS[@]}"; do
    NET_ID_TRIM=$(echo "$NET_ID" | xargs)
    RPC_URL="${NETWORK_RPC[$NET_ID_TRIM]}"
    PRIVKEY="${NETWORK_PRIVKEY[$NET_ID_TRIM]}"
    ENV_FILE="${NETWORK_ENVS_FILE[$NET_ID_TRIM]}"
    BROKER_CONFIGS+="
[program:broker${NET_ID_TRIM}]
command=/bin/bash -c \"source ${ENV_FILE} && /app/broker --db-url sqlite:///db/broker${NET_ID_TRIM}.db --config-file /app/broker${NET_ID_TRIM}.toml --bento-api-url http://localhost:8081\"
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10800
priority=60
stdout_logfile=/var/log/broker${NET_ID_TRIM}.log
redirect_stderr=true
environment=RUST_LOG=\"info,broker=debug,boundless_market=debug\",PRIVATE_KEY=\"${PRIVKEY}\",RPC_URL=\"${RPC_URL}\",POSTGRES_HOST=\"localhost\",POSTGRES_DB=\"taskdb\",POSTGRES_PORT=\"5432\",POSTGRES_USER=\"worker\",POSTGRES_PASS=\"password\"
"
    cp broker-template.toml /app/broker${NET_ID_TRIM}.toml
done

cat <<EOF >/etc/supervisor/conf.d/boundless.conf
[supervisord]
nodaemon=false
logfile=/var/log/supervisord.log
pidfile=/var/run/supervisord.pid
loglevel=info
strip_ansi=true

[group:dependencies]
programs=redis,postgres,minio,grafana

[group:bento]
programs=exec_agent0,exec_agent1,aux_agent,rest_api

[group:broker]
programs=

[program:redis]
command=/usr/bin/redis-server --port 6379
directory=/data/redis
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=10
stdout_logfile=/var/log/redis.log
redirect_stderr=true
environment=HOME="/data/redis"

[program:postgres]
command=/usr/lib/postgresql/16/bin/postgres -D /data/postgresql -c config_file=/etc/postgresql/16/main/postgresql.conf -p 5432
directory=/data/postgresql
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=20
stdout_logfile=/var/log/postgres.log
redirect_stderr=true
environment=POSTGRES_DB="taskdb",POSTGRES_USER="worker",POSTGRES_PASSWORD="password"
user=postgres

[program:minio]
command=/usr/local/bin/minio server /data --console-address ":9001"
directory=/data/minio
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=30
stdout_logfile=/var/log/minio.log
redirect_stderr=true
environment=MINIO_ROOT_USER="admin",MINIO_ROOT_PASSWORD="password",MINIO_DEFAULT_BUCKETS="workflow"

[program:grafana]
command=/usr/share/grafana/bin/grafana-server --homepath=/usr/share/grafana --config=/etc/grafana/grafana.ini
directory=/var/lib/grafana
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=40
stdout_logfile=/var/log/grafana.log
redirect_stderr=true
environment=GF_SECURITY_ADMIN_USER="admin",GF_SECURITY_ADMIN_PASSWORD="admin",GF_LOG_LEVEL="WARN",POSTGRES_HOST="localhost",POSTGRES_DB="taskdb",POSTGRES_PORT="5432",POSTGRES_USER="worker",POSTGRES_PASSWORD="password",GF_INSTALL_PLUGINS="frser-sqlite-datasource"

[program:exec_agent0]
command=/app/agent -t exec --segment-po2 $MIN_SEGMENT_SIZE --redis-ttl 57600
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/exec_agent0.log
redirect_stderr=true
environment=DATABASE_URL="postgresql://worker:password@localhost:5432/taskdb",REDIS_URL="redis://localhost:6379",S3_URL="http://localhost:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1",RISC0_KECCAK_PO2="17",POVW_LOG_ID="${POVW_LOG_ID}"

[program:exec_agent1]
command=/app/agent -t exec --segment-po2 $MIN_SEGMENT_SIZE --redis-ttl 57600
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/exec_agent1.log
redirect_stderr=true
environment=DATABASE_URL="postgresql://worker:password@localhost:5432/taskdb",REDIS_URL="redis://localhost:6379",S3_URL="http://localhost:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1",RISC0_KECCAK_PO2="17",POVW_LOG_ID="${POVW_LOG_ID}"

[program:aux_agent]
command=/app/agent -t aux --monitor-requeue --redis-ttl 57600
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/aux_agent.log
redirect_stderr=true
environment=DATABASE_URL="postgresql://worker:password@localhost:5432/taskdb",REDIS_URL="redis://localhost:6379",S3_URL="http://localhost:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1",POVW_LOG_ID="${POVW_LOG_ID}"

[program:rest_api]
command=/app/rest_api --bind-addr 0.0.0.0:8081 --snark-timeout 180
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/rest_api.log
redirect_stderr=true
environment=DATABASE_URL="postgresql://worker:password@localhost:5432/taskdb",REDIS_URL="redis://localhost:6379",S3_URL="http://localhost:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1",POVW_LOG_ID="${POVW_LOG_ID}"
EOF

cat <<EOF >>/etc/supervisor/conf.d/boundless.conf
$GPU_AGENT_CONFIGS
$BROKER_CONFIGS
EOF

GPU_AGENT_NAMES=$(echo "$GPU_AGENT_CONFIGS" | grep -oP '(?<=\[program:)[^]]+' | tr '\n' ' ')
BROKER_NAMES=$(echo "$BROKER_CONFIGS" | grep -oP '(?<=\[program:)[^]]+' | tr '\n' ' ')

sed -i "/^\[group:bento\]/{
    n
    s/^programs *=.*/&,$(echo $GPU_AGENT_NAMES | tr ' ' ',')/
}" /etc/supervisor/conf.d/boundless.conf

sed -i "/^\[group:broker\]/{
    n
    s/^programs *=.*/&$(echo $BROKER_NAMES | tr ' ' ',')/
}" /etc/supervisor/conf.d/boundless.conf

mkdir -p /data/redis
mkdir -p /data/postgresql
mkdir -p /data/minio
echo

echo "-----正在启动依赖服务-----"
supervisorctl update
supervisorctl start dependencies:*
supervisorctl status
echo

echo "-----正在初始化数据库-----"
curl -L "https://raw.githubusercontent.com/walirt/boundless-prover/refs/heads/main/initdb.sh" -o initdb.sh
chmod +x initdb.sh
./initdb.sh
mkdir /db
supervisorctl restart dependencies:postgres
echo

echo "-----正在启动bento服务-----"
supervisorctl start bento:*
supervisorctl status
echo

echo "Prover节点设置完成"
echo "请重启控制台或运行以下命令"
echo "1. source $HOME/.cargo/env"
echo "2. source $HOME/.bashrc"

echo "Prover主目录: /app"
echo "日志目录: /var/log"
echo "Broker配置文件路径: /app/broker*.toml"
echo "Supervisord配置文件路径: /etc/supervisor/conf.d/boundless.conf"

if [ "$SILENT_MODE" = true ]; then
    echo
    echo "=========================================="
    echo "警告：使用了静默模式！"
    echo "=========================================="
    echo "已使用默认值："
    echo "- GPU ID: 所有可用GPU"
    echo "- 网络: 3 (Base Mainnet)"
    echo "- RPC URLs: 占位符URL（需要更新）"
    echo "- 私钥: 占位符私钥（需要更新）"
    echo
    echo "重要提醒：启动服务前请更新以下内容："
    echo "1. 环境变量中的RPC URLs"
    echo "2. 环境变量中的私钥"
    echo "3. 检查 /etc/supervisor/conf.d/boundless.conf"
    echo "=========================================="
fi

echo
echo "基本命令: "
echo "-----运行测试证明-----"
echo "RUST_LOG=info bento_cli -c 32"
echo 
echo "-----Prover基准测试-----"
echo "export RPC_URL=<目标链RPC_URL>"
echo "boundless proving benchmark --request-ids <IDS>"
echo 
echo "-----存款和质押-----"
echo "export RPC_URL=<目标链RPC_URL>"
echo "export PRIVATE_KEY=<私钥>"
echo "source /app/.env.<目标链名称>"
echo "boundless account deposit-stake <要存入的USDC>"
echo "boundless account stake-balance"
echo "boundless account withdraw-stake <要提取的金额>"
echo
echo "-----服务管理-----"
echo "依赖服务:"
echo "supervisorctl start dependencies:*"
echo "supervisorctl stop dependencies:*"
echo "supervisorctl restart dependencies:*"
echo "Bento:"
echo "supervisorctl start bento:*"
echo "supervisorctl stop bento:*"
echo "supervisorctl restart bento:*"
echo "Broker:"
echo "supervisorctl start broker:*"
echo "supervisorctl stop broker:*"
echo "supervisorctl restart broker:*"
