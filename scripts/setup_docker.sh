#!/usr/bin/env bash
# =============================================================================
# scripts/setup_docker.sh
# Docker 環境セットアップスクリプト — 本番サーバー (192.168.50.112) 上で実行
#
# 実行内容:
#   1. docker.io + docker-compose-plugin インストール
#   2. mdlユーザーを docker グループに追加
#   3. /var/log/cocoro-llm ディレクトリ作成 (755)
#   4. /models ディレクトリ作成 (4TB NVMe 直下)
#   5. Docker 動作確認 (sudoなし)
#
# 前提:
#   - Debian 13 Trixie
#   - sudo 権限があること
#
# 実行方法:
#   sudo bash scripts/setup_docker.sh
# =============================================================================

set -euo pipefail

# ── 色 ──────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()       { log_error "$*"; exit 1; }

# root チェック
if [[ "$(id -u)" -ne 0 ]]; then
    die "このスクリプトは root 権限で実行してください: sudo bash $0"
fi

# 実行ユーザー確認（sudo元ユーザー）
RUN_AS_USER="${SUDO_USER:-mdl}"
log_info "セットアップ対象ユーザー: ${RUN_AS_USER}"

# ── Step 1: Docker インストール ────────────────────────────────────────────
log_info "=== Step 1: Docker インストール ==="

if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version 2>/dev/null || echo "不明")
    log_warn "Docker は既にインストールされています: ${DOCKER_VER}"
    log_warn "スキップします。アップグレードが必要な場合は手動で実行してください。"
else
    log_info "パッケージリストを更新中..."
    apt-get update -qq

    log_info "依存パッケージをインストール中..."
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Docker 公式 APT リポジトリを追加
    log_info "Docker 公式 APT リポジトリを追加中..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    log_info "Docker をインストール中..."
    apt-get update -qq
    apt-get install -y \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log_ok "Docker インストール完了: $(docker --version)"
fi

# Docker サービス起動・自動起動設定
log_info "Docker サービスを起動中..."
systemctl enable docker --now
log_ok "Docker サービス: $(systemctl is-active docker)"

# ── Step 2: mdlユーザーを docker グループに追加 ───────────────────────────
log_info "=== Step 2: docker グループ設定 ==="

if id -nG "${RUN_AS_USER}" | grep -qw docker; then
    log_warn "${RUN_AS_USER} は既に docker グループに所属しています"
else
    usermod -aG docker "${RUN_AS_USER}"
    log_ok "${RUN_AS_USER} を docker グループに追加しました"
    log_warn "グループ変更を有効にするには再ログインが必要です:"
    log_warn "  newgrp docker   ← 現在のセッションで即時有効化"
    log_warn "  または一度ログアウト・ログイン"
fi

# ── Step 3: ログディレクトリ作成 ────────────────────────────────────────────
log_info "=== Step 3: ログディレクトリ作成 ==="

LOG_DIR="/var/log/cocoro-llm"
mkdir -p "${LOG_DIR}"
chmod 755 "${LOG_DIR}"
chown "${RUN_AS_USER}:${RUN_AS_USER}" "${LOG_DIR}"
log_ok "ログディレクトリ: ${LOG_DIR} (755, owned by ${RUN_AS_USER})"

# ── Step 4: /models ディレクトリ作成 ─────────────────────────────────────
log_info "=== Step 4: /models ディレクトリ作成 ==="

MODELS_DIR="/models"
if [[ -d "${MODELS_DIR}" ]]; then
    log_warn "${MODELS_DIR} は既に存在します"
    AVAIL_GB=$(df "${MODELS_DIR}" --output=avail -BG | tail -1 | tr -d 'G')
    log_info "  空き容量: ${AVAIL_GB}GB"
else
    mkdir -p "${MODELS_DIR}"
    log_ok "${MODELS_DIR} を作成しました"
fi

chmod 755 "${MODELS_DIR}"
chown "${RUN_AS_USER}:${RUN_AS_USER}" "${MODELS_DIR}"
log_ok "/models: 755, owned by ${RUN_AS_USER}"

# ── Step 5: Docker 動作確認 ──────────────────────────────────────────────
log_info "=== Step 5: Docker 動作確認 (sudo なし) ==="

# newgrp を使わず sg で検証
if su - "${RUN_AS_USER}" -c "docker info &>/dev/null"; then
    log_ok "Docker: sudo なしで動作しています ✓"
else
    log_warn "Docker: sudo なし確認に失敗しました"
    log_warn "  再ログイン後に 'docker info' を試してください"
fi

# docker compose v2 確認
if su - "${RUN_AS_USER}" -c "docker compose version &>/dev/null"; then
    COMPOSE_VER=$(su - "${RUN_AS_USER}" -c "docker compose version" 2>/dev/null || echo "不明")
    log_ok "Docker Compose: ${COMPOSE_VER}"
else
    log_error "docker compose が使えません。docker-compose-plugin の確認が必要です。"
fi

# ── 完了サマリー ──────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════"
echo "  Docker セットアップ完了"
echo "════════════════════════════════════════════════"
echo "  Docker     : $(docker --version 2>/dev/null | head -1)"
echo "  ログDir    : ${LOG_DIR}"
echo "  モデルDir  : ${MODELS_DIR}"
echo ""
echo "  次のステップ:"
echo "  1. (必要なら) newgrp docker  ← sudo なしでdocker使えるようにする"
echo "  2. cp .env.example .env && vi .env  ← HF_TOKEN等を設定"
echo "  3. bash scripts/model_download.sh  ← モデルDL（数時間）"
echo "  4. bash scripts/start_all.sh       ← 全サービス起動"
echo "════════════════════════════════════════════════"
