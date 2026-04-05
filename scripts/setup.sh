#!/usr/bin/env bash
# =============================================================================
# scripts/setup.sh
# 初回セットアップスクリプト（llm-server上で実行）
#
# このスクリプトは以下を自動実行します:
#   1. 必要ディレクトリ作成
#   2. .envファイル確認
#   3. DockerとDocker Composeのインストール確認
#   4. モデル保存ディレクトリ作成 (/models/)
#   5. ログディレクトリ作成 (/var/log/cocoro-llm/)
#   6. systemdサービスファイル生成（vllm-primary, vllm-secondary）
#
# 前提:
#   - setup_nvidia.sh 実行済み（CUDA 12.8 + NVIDIAドライバ）
#   - setup_vllm.sh 実行済み（/opt/vllm-env）
#
# 実行方法:
#   sudo bash scripts/setup.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${BLUE}━━━ $* ━━━${NC}"; }

# root確認
[[ $EUID -ne 0 ]] && { log_error "sudo bash scripts/setup.sh で実行してください"; exit 1; }

log_step "Step 1: ディレクトリ作成"

# モデルディレクトリ
mkdir -p /models/llama4-scout /models/qwen35-32b
chmod 755 /models
log_ok "/models/ 作成完了"

# ログディレクトリ
mkdir -p /var/log/cocoro-llm
chmod 755 /var/log/cocoro-llm
log_ok "/var/log/cocoro-llm/ 作成完了"

log_step "Step 2: .env確認"

if [[ ! -f "${REPO_DIR}/.env" ]]; then
    cp "${REPO_DIR}/.env.example" "${REPO_DIR}/.env"
    log_warn ".env.example をコピーしました: ${REPO_DIR}/.env"
    log_warn "HF_TOKEN と LITELLM_MASTER_KEY を設定してください"
else
    log_ok ".env: 存在確認"
fi

log_step "Step 3: Docker確認"

if ! command -v docker &>/dev/null; then
    log_info "Dockerをインストールしています..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    usermod -aG docker mdl
    log_ok "Dockerインストール完了"
else
    log_ok "Docker: $(docker --version)"
fi

# Docker Compose v2 確認
if ! docker compose version &>/dev/null; then
    log_info "Docker Compose v2 をインストール中..."
    apt-get install -y docker-compose-plugin
    log_ok "docker compose インストール完了"
else
    log_ok "Docker Compose: $(docker compose version --short)"
fi

log_step "Step 4: CUDA確認"

if [[ -f /usr/local/cuda/bin/nvcc ]]; then
    CUDA_VER=$(/usr/local/cuda/bin/nvcc --version | grep "release" | awk '{print $6}' | tr -d ',V')
    log_ok "CUDA: ${CUDA_VER}"
else
    log_warn "CUDAが見つかりません。sudo bash scripts/setup_nvidia.sh を先に実行してください"
fi

if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    log_ok "GPU: ${GPU_NAME}"
else
    log_warn "nvidia-smiが見つかりません。ドライバを確認してください"
fi

log_step "Step 5: vLLM確認"

if [[ -f /opt/vllm-env/bin/python ]]; then
    VLLM_VER=$(/opt/vllm-env/bin/python -c "import vllm; print(vllm.__version__)" 2>/dev/null || echo "不明")
    log_ok "vLLM: ${VLLM_VER} (/opt/vllm-env)"
else
    log_warn "vLLM仮想環境が見つかりません。sudo bash scripts/setup_vllm.sh を実行してください"
fi

log_step "Step 6: systemdサービスファイル生成"

# vllm-primary.service
cat > /etc/systemd/system/vllm-primary.service << EOF
[Unit]
Description=vLLM Primary - Llama 4 Scout 109B
After=network.target
Wants=network.target

[Service]
Type=simple
User=mdl
Group=mdl
WorkingDirectory=${REPO_DIR}
ExecStartPre=/bin/bash -c 'source /usr/local/bin/vllm-activate'
ExecStart=/bin/bash -c 'source /usr/local/bin/vllm-activate && bash ${REPO_DIR}/vllm/start_primary.sh'
Restart=on-failure
RestartSec=30
StandardOutput=journal
StandardError=journal
Environment=HOME=/home/mdl

[Install]
WantedBy=multi-user.target
EOF
log_ok "systemd: vllm-primary.service"

# vllm-secondary.service
cat > /etc/systemd/system/vllm-secondary.service << EOF
[Unit]
Description=vLLM Secondary - Qwen 3.5 32B
After=network.target vllm-primary.service
Wants=vllm-primary.service

[Service]
Type=simple
User=mdl
Group=mdl
WorkingDirectory=${REPO_DIR}
ExecStart=/bin/bash -c 'source /usr/local/bin/vllm-activate && bash ${REPO_DIR}/vllm/start_secondary.sh'
Restart=on-failure
RestartSec=60
StandardOutput=journal
StandardError=journal
Environment=HOME=/home/mdl

[Install]
WantedBy=multi-user.target
EOF
log_ok "systemd: vllm-secondary.service"

systemctl daemon-reload
log_ok "systemd daemon-reload 完了"

# ── 完了 ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  セットアップ完了！                                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo "次のステップ:"
echo "  1. モデルDL : bash scripts/model_download.sh"
echo "  2. vLLM起動 : systemctl start vllm-primary vllm-secondary"
echo "  3. Docker   : docker compose -f docker/docker-compose.yml up -d"
echo "  4. 確認     : bash scripts/health_check.sh"
echo ""
