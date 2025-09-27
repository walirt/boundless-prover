#!/bin/bash

SILENT_MODE=false
SKIP_CLI_TOOLS=false
while getopts "sc" opt; do
    case $opt in
        s)
            SILENT_MODE=true
            echo "Running in silent mode with default values..."
            ;;
        c)
            SKIP_CLI_TOOLS=true
            echo "Skipping CLI tools installation..."
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo "Usage: $0 [-s] [-c]"
            echo "  -s: Silent mode (use default values without prompts)"
            echo "  -c: Skip CLI tools installation"
            exit 1
            ;;
    esac
done

apt update
apt install -y curl nvtop git supervisor build-essential pkg-config libssl-dev python3-dev
echo

echo "-----Installing rust-----"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source $HOME/.cargo/env
echo

echo "-----Installing rzup and RISC Zero toolchain-----"
curl -L https://risczero.com/install | bash
source $HOME/.bashrc
/root/.risc0/bin/rzup install
/root/.risc0/bin/rzup install risc0-groth16
echo

echo "-----Installing bento components-----"
apt install -y redis postgresql-16 adduser libfontconfig1 musl

wget https://dl.min.io/server/minio/release/linux-amd64/archive/minio_20250613113347.0.0_amd64.deb -O minio.deb
dpkg -i minio.deb

curl -L "https://zzno.de/boundless/grafana-enterprise_11.0.0_amd64.deb" -o grafana-enterprise_11.0.0_amd64.deb
dpkg -i grafana-enterprise_11.0.0_amd64.deb
echo

echo "-----Downloading prover binaries-----"
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

echo "-----Verifying /app files sha256sum-----"
declare -A FILES_SHA256
FILES_SHA256["/app/broker"]="216a792c4bb1444a0ce7a447ea2cad0b24e660601baa49057f77b37ac9f4ad74"
FILES_SHA256["/app/broker-stress"]="024d916463d8f24fb9d12857b6f1dbdc016f972e8d8b82434804e077e0fe6231"
FILES_SHA256["/app/agent"]="3be0a008af2ae2a9d5cfacbfbb3f75d4a4fd70b82152ae3e832b500ad468f5a0"
FILES_SHA256["/app/rest_api"]="02a0c87b3bfc1fd738d6714ee24fb32fbcb7887bfe46321c3eed2061c581a87a"
FILES_SHA256["/root/.cargo/bin/bento_cli"]="7af2fe49f75acf95e06476e55e6a91343c238b0cf5696d1cae80be54fcc17b45"

INTEGRITY_PASS=true

for file in "${!FILES_SHA256[@]}"; do
    if [ ! -f "$file" ]; then
        echo "File missing: $file"
        INTEGRITY_PASS=false
        continue
    fi
    actual_sum=$(sha256sum "$file" | awk '{print $1}')
    expected_sum="${FILES_SHA256[$file]}"
    if [ "$actual_sum" != "$expected_sum" ]; then
        echo "File integrity check failed: $file"
        echo "  Expected: $expected_sum"
        echo "  Actual:   $actual_sum"
        INTEGRITY_PASS=false
    else
        echo "File integrity check passed: $file"
    fi
done

if [ "$INTEGRITY_PASS" = false ]; then
    echo "Some files failed the sha256sum check. Please verify file integrity and try again."
    exit 1
else
    echo "All files passed sha256sum integrity check."
fi
echo

echo "-----Copying config files-----"
git clone https://github.com/boundless-xyz/boundless.git
cd boundless
git checkout v1.0.0
if [ "$SKIP_CLI_TOOLS" = false ]; then
    git submodule update --init --recursive
    cargo install --path crates/boundless-cli --locked boundless-cli
fi
cp -rf dockerfiles/grafana/* /etc/grafana/provisioning/
echo

echo "-----Generating supervisord configuration file-----"
nvidia-smi -L

if [ "$SILENT_MODE" = true ]; then
    GPU_IDS=$(nvidia-smi --query-gpu=index --format=csv,noheader | tr '\n' ',' | sed 's/,$//')
    echo "Using all available GPUs: $GPU_IDS"
else
    read -p "Please input the GPU ID you need to run according to the printed GPU information (e.g. 0,1 default all): " GPU_IDS
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

echo "Based on GPU VRAM, the minimum SEGMENT_SIZE is: $MIN_SEGMENT_SIZE"

declare -A NETWORK_NAMES
NETWORK_NAMES["1"]="Eth Sepolia"
NETWORK_NAMES["2"]="Base Sepolia"
NETWORK_NAMES["3"]="Base Mainnet"

if [ "$SILENT_MODE" = false ]; then
    for id in $(for key in "${!NETWORK_NAMES[@]}"; do echo "$key"; done | sort -n); do
        echo "$id) ${NETWORK_NAMES[$id]}"
    done
fi

if [ "$SILENT_MODE" = true ]; then
    NETWORK_IDS="3"
    echo "Using default network: $NETWORK_IDS (Base Mainnet)"
else
    read -p "Please input the network you need to run (e.g. 1,2,3 default 3): " NETWORK_IDS
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
        echo "Using default RPC for ${NETWORK_NAME}: $rpc"
        echo "Using default private key for ${NETWORK_NAME}: $privkey"
        echo "WARNING: Please update RPC URL and private key in the configuration files before starting services!"
    else
        read -p "Please input the RPC URL of ${NETWORK_NAME}: " rpc
        read -p "Please input the private key of ${NETWORK_NAME}: " privkey
    fi
    
    NETWORK_RPC["$NET_ID_TRIM"]="$rpc"
    NETWORK_PRIVKEY["$NET_ID_TRIM"]="$privkey"
done

POVW_LOG_ID=""
read -p "Please input the POVW Log ID: " POVW_LOG_ID

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
    BROKER_CONFIGS+="
[program:broker${NET_ID_TRIM}]
command=/app/broker --db-url sqlite:///db/broker${NET_ID_TRIM}.db --config-file /app/broker${NET_ID_TRIM}.toml --bento-api-url http://localhost:8081
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

echo "-----Starting dependencies services-----"
supervisorctl update
supervisorctl start dependencies:*
supervisorctl status
echo

echo "-----Initializing database-----"
curl -L "https://raw.githubusercontent.com/walirt/boundless-prover/refs/heads/main/initdb.sh" -o initdb.sh
chmod +x initdb.sh
./initdb.sh
mkdir /db
supervisorctl restart dependencies:postgres
echo

echo "-----Starting bento services-----"
supervisorctl start bento:*
supervisorctl status
echo

echo "Prover node setup complete"
echo "Please restart the console or run the following command"
echo "1. source $HOME/.cargo/env"
echo "2. source $HOME/.bashrc"

echo "Prover main directory: /app"
echo "Log directory: /var/log"
echo "Broker configuration file path: /app/broker*.toml"
echo "Supervisord configuration file path: /etc/supervisor/conf.d/boundless.conf"

if [ "$SILENT_MODE" = true ]; then
    echo
    echo "=========================================="
    echo "WARNING: Silent mode was used!"
    echo "=========================================="
    echo "Default values were used for:"
    echo "- GPU ID: All available GPUs"
    echo "- Network: 3 (Base Mainnet)"
    echo "- RPC URLs: Placeholder URLs (need to be updated)"
    echo "- Private Keys: Placeholder key (need to be updated)"
    echo
    echo "IMPORTANT: Before starting services, please update:"
    echo "1. RPC URLs in the environment variables"
    echo "2. Private keys in the environment variables"
    echo "3. Review /etc/supervisor/conf.d/boundless.conf"
    echo "=========================================="
fi

echo
echo "Basic commands: "
echo "-----Running a Test Proof-----"
echo "RUST_LOG=info bento_cli -c 32"
echo 
echo "-----Prover benchmark-----"
echo "export RPC_URL=<TARGET_CHAIN_RPC_URL>"
echo "boundless proving benchmark --request-ids <IDS>"
echo 
echo "-----Deposit and Stake-----"
echo "export RPC_URL=<TARGET_CHAIN_RPC_URL>"
echo "export PRIVATE_KEY=<PRIVATE_KEY>"
echo "source /app/.env.<TARGET_CHAIN_NAME>"
echo "boundless account deposit-stake <USDC_TO_DEPOSIT>"
echo "boundless account stake-balance"
echo "boundless account withdraw-stake <AMOUNT_TO_WITHDRAW>"
echo
echo "-----Service management-----"
echo "Dependencies:"
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
