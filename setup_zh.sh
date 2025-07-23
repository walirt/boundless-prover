#!/bin/bash

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
curl -L "https://zzno.de/boundless/agent" -o /app/agent
curl -L "https://zzno.de/boundless/broker" -o /app/broker
curl -L "https://zzno.de/boundless/prover" -o /app/prover
curl -L "https://zzno.de/boundless/rest_api" -o /app/rest_api
curl -L "https://zzno.de/boundless/stark_verify" -o /app/stark_verify
curl -L "https://zzno.de/boundless/stark_verify.cs" -o /app/stark_verify.cs
curl -L "https://zzno.de/boundless/stark_verify.dat" -o /app/stark_verify.dat
curl -L "https://zzno.de/boundless/stark_verify_final.pk.dmp" -o /app/stark_verify_final.pk.dmp

chmod +x /app/agent
chmod +x /app/broker
chmod +x /app/prover
chmod +x /app/rest_api
chmod +x /app/stark_verify

echo "-----正在验证/app文件sha256sum-----"
declare -A FILES_SHA256
FILES_SHA256["/app/agent"]="63ff8efead376f5a515a1371f6abf14ffa7018b9a4226a701ab1758b48281ffd"
FILES_SHA256["/app/broker"]="a705429568d9abce259f207c6b20968423b221dad0c4fe205d1ace4d599654c0"
FILES_SHA256["/app/prover"]="d4507413897a37c28699f2f318731ca9ec4784ece69bdf5f1f224bd87ab8f119"
FILES_SHA256["/app/rest_api"]="180a94d5eca85d7213d6c002e677a6a491d7dcd439ef0543c8435227dd99546d"
FILES_SHA256["/app/stark_verify"]="7dc5321854d41d9d3ff3da651503fe405082c03c80d68c5f5186b5e77673f58c"
FILES_SHA256["/app/stark_verify.cs"]="0670f7c8ce8fe757d0cf4808c5d5cd92c85ac7a96ea98170c2f6f756d49e80b5"
FILES_SHA256["/app/stark_verify.dat"]="7832c9694eed855a5bdb120e972cce402a133f428513185f97e1bdfdde27a2bc"
FILES_SHA256["/app/stark_verify_final.pk.dmp"]="6d76b07e187e3329b1d82498a5f826366c3b2e04fc6d99de3d790248eb1ea71f"

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

echo "-----正在安装CLI工具-----"
git clone https://github.com/boundless-xyz/boundless.git
cd boundless
git checkout release-0.13
git submodule update --init --recursive
cargo install --locked --git https://github.com/risc0/risc0 bento-client --branch release-2.1 --bin bento_cli
cargo install --path crates/boundless-cli --locked boundless-cli
echo

echo "-----正在复制配置文件-----"
cp -rf dockerfiles/grafana/* /etc/grafana/provisioning/
cp .env.base /app/.env.base
cp .env.base-sepolia /app/.env.base-sepolia
cp .env.eth-sepolia /app/.env.eth-sepolia
echo

echo "-----正在生成supervisord配置文件-----"
nvidia-smi -L
read -p "请根据打印的GPU信息输入您需要运行的GPU ID（例如 0,1 ，默认 0）: " GPU_IDS
GPU_IDS=${GPU_IDS:-0}

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

for id in $(for key in "${!NETWORK_NAMES[@]}"; do echo "$key"; done | sort -n); do
    echo "$id) ${NETWORK_NAMES[$id]}"
done

read -p "请输入您需要运行的网络（例如 1,2 ，默认 1,2）: " NETWORK_IDS
NETWORK_IDS=${NETWORK_IDS:-1,2}

IFS=',' read -ra NET_IDS <<< "$NETWORK_IDS"
declare -A NETWORK_RPC
declare -A NETWORK_PRIVKEY

for NET_ID in "${NET_IDS[@]}"; do
    NET_ID_TRIM=$(echo "$NET_ID" | xargs)
    NETWORK_NAME="${NETWORK_NAMES[$NET_ID_TRIM]}"
    read -p "请输入${NETWORK_NAME}的RPC地址: " rpc
    read -p "请输入${NETWORK_NAME}的私钥: " privkey
    NETWORK_RPC["$NET_ID_TRIM"]="$rpc"
    NETWORK_PRIVKEY["$NET_ID_TRIM"]="$privkey"
done

GPU_IDS_ARRAY=()
IFS=',' read -ra GPU_IDS_ARRAY <<< "$GPU_IDS"
GPU_AGENT_CONFIGS=""
for idx in "${!GPU_IDS_ARRAY[@]}"; do
    GPU_ID_TRIM=$(echo "${GPU_IDS_ARRAY[$idx]}" | xargs)
    GPU_AGENT_CONFIGS+="
[program:gpu_prove_agent${idx}]
command=/app/agent -t prove
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/gpu_prove_agent${idx}.log
redirect_stderr=true
environment=DATABASE_URL=\"postgresql://worker:password@localhost:5432/taskdb\",REDIS_URL=\"redis://localhost:6379\",S3_URL=\"http://localhost:9000\",S3_BUCKET=\"workflow\",S3_ACCESS_KEY=\"admin\",S3_SECRET_KEY=\"password\",RUST_LOG=\"info\",RUST_BACKTRACE=\"1\",CUDA_VISIBLE_DEVICES=\"${GPU_ID_TRIM}\"
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
programs=exec_agent0,exec_agent1,aux_agent,snark_agent,rest_api

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
command=/app/agent -t exec --segment-po2 $MIN_SEGMENT_SIZE
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/exec_agent0.log
redirect_stderr=true
environment=DATABASE_URL="postgresql://worker:password@localhost:5432/taskdb",REDIS_URL="redis://localhost:6379",S3_URL="http://localhost:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1",RISC0_KECCAK_PO2="17"

[program:exec_agent1]
command=/app/agent -t exec --segment-po2 $MIN_SEGMENT_SIZE
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/exec_agent1.log
redirect_stderr=true
environment=DATABASE_URL="postgresql://worker:password@localhost:5432/taskdb",REDIS_URL="redis://localhost:6379",S3_URL="http://localhost:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1",RISC0_KECCAK_PO2="17"

[program:aux_agent]
command=/app/agent -t aux --monitor-requeue
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/aux_agent.log
redirect_stderr=true
environment=DATABASE_URL="postgresql://worker:password@localhost:5432/taskdb",REDIS_URL="redis://localhost:6379",S3_URL="http://localhost:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1"

[program:snark_agent]
command=/bin/bash -c "ulimit -s 90000000 && /app/agent -t snark"
directory=/app
autostart=false
autorestart=true
startsecs=5
stopwaitsecs=10
priority=50
stdout_logfile=/var/log/snark_agent.log
redirect_stderr=true
environment=DATABASE_URL="postgresql://worker:password@localhost:5432/taskdb",REDIS_URL="redis://localhost:6379",S3_URL="http://localhost:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1"
startretries=3

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
environment=DATABASE_URL="postgresql://worker:password@localhost:5432/taskdb",REDIS_URL="redis://localhost:6379",S3_URL="http://localhost:9000",S3_BUCKET="workflow",S3_ACCESS_KEY="admin",S3_SECRET_KEY="password",RUST_LOG="info",RUST_BACKTRACE="1"
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
