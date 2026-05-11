#!/usr/bin/env bash
# =============================================================================
# scripts/first_setup.sh — cocoro-llm-server 初回セットアップ
#
# 実行方法:
#   bash scripts/first_setup.sh
#
# やること:
#   1. LITELLM_MASTER_KEY を自動生成
#   2. サーバーのLAN IPを自動検出
#   3. HF_TOKEN / ANTHROPIC_API_KEY を対話式で設定（スキップ可）
#   4. .env を作成
#   5. docker compose up -d
#   6. 接続情報を表示
# =============================================================================

set -euo pipefail

# ── カラー ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERROR]${NC} $*" >&2; }
section() { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ── ヘッダー ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║   cocoro-llm-server 初回セットアップ                 ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ── 前提確認 ─────────────────────────────────────────────────────────────────
section "前提確認"

if [[ ! -f "${REPO_DIR}/.env.example" ]]; then
    err ".env.example が見つかりません。リポジトリのルートから実行してください。"
    exit 1
fi

if ! command -v docker &>/dev/null; then
    err "Docker がインストールされていません。"
    err "先に bash scripts/setup_docker.sh を実行してください。"
    exit 1
fi

if ! docker compose version &>/dev/null; then
    err "docker compose が使えません。Docker Engine を確認してください。"
    exit 1
fi

ok "Docker: $(docker --version | head -1)"
ok "Docker Compose: $(docker compose version)"

# ── Tailscale チェック（任意・推奨）──────────────────────────────────────────
section "Tailscale チェック（任意・推奨）"

echo ""
echo -e "${BOLD}【ネットワーク前提について】${NC}"
echo "  クライアントPC（OpenCode/Claude Code を使うPC）は、このサーバーに"
echo "  ネットワーク的に到達できる必要があります。"
echo ""
echo -e "  ${BOLD}重要:${NC} 同じLAN（同じWiFi/同じルーター下）にいない場合は、"
echo "  Tailscale などの VPN で同じネットワークに置く必要があります。"
echo "  そうしないとクライアントから接続できません。"
echo ""

if command -v tailscale &>/dev/null; then
    if tailscale status &>/dev/null; then
        TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || echo "")
        ok "Tailscale: 稼働中（IP: ${TS_IP}）"
        info "クライアントPCにも同じTailscaleアカウントでログインしてください。"
    else
        warn "Tailscale はインストール済みですが、ログインされていません。"
        echo "  以下を実行してログインしてください:"
        echo "    sudo tailscale up"
    fi
else
    warn "Tailscale が見つかりません。"
    echo ""
    echo "  リモート（外出先・別WiFi）から接続したい場合は、以下でインストールできます:"
    echo "    curl -fsSL https://tailscale.com/install.sh | sh"
    echo "    sudo tailscale up"
    echo ""
    echo "  同じLAN内のクライアントしか使わない場合は、このまま続行できます。"
    echo ""
    read -rp "  続行しますか？ [Y/n]: " continue_ans
    if [[ "$continue_ans" =~ ^[Nn]$ ]]; then
        info "セットアップを中断しました。"
        exit 0
    fi
fi

# ── .env チェック ─────────────────────────────────────────────────────────────
section ".env 設定"

ENV_PATH="${REPO_DIR}/.env"

if [[ -f "$ENV_PATH" ]]; then
    warn ".env がすでに存在します。"
    read -rp "  上書きしますか？ [y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        info ".env はそのまま使用します。"
        SKIP_ENV=true
    else
        SKIP_ENV=false
    fi
else
    SKIP_ENV=false
fi

if [[ "$SKIP_ENV" == false ]]; then

    # ── LITELLM_MASTER_KEY 自動生成 ────────────────────────────────────────
    MASTER_KEY="coco-$(openssl rand -hex 16)"
    ok "APIキーを自動生成しました: ${MASTER_KEY}"

    # ── HF_TOKEN（任意）────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}【HuggingFace トークンについて】${NC}"
    echo "  モデル（Qwen3-Coder-Next-FP8）を初めてダウンロードする場合に必要です。"
    echo "  → https://huggingface.co/settings/tokens で取得できます。"
    echo "  ※ すでにサーバーにモデルがある場合はスキップできます。"
    echo ""
    read -rp "  HuggingFace トークンを入力（スキップは Enter）: " HF_TOKEN_INPUT
    HF_TOKEN_VAL="${HF_TOKEN_INPUT:-}"

    if [[ -z "$HF_TOKEN_VAL" ]]; then
        warn "HF_TOKEN をスキップしました。モデルがない場合は起動に失敗します。"
        HF_TOKEN_LINE="HF_TOKEN=             # 未設定（モデルDLが必要な場合は設定してください）"
    else
        ok "HF_TOKEN を設定しました。"
        HF_TOKEN_LINE="HF_TOKEN=${HF_TOKEN_VAL}"
    fi

    # ── ANTHROPIC_API_KEY（任意）──────────────────────────────────────────
    echo ""
    echo -e "${BOLD}【Anthropic API キーについて】${NC}"
    echo "  Claude（AI）を「smart-coder のフォールバック」として使う場合に必要です。"
    echo "  → https://console.anthropic.com/settings/keys で取得できます。"
    echo "  ※ ローカルLLMだけ使う場合はスキップできます。"
    echo "    （ただし smart-coder のフォールバックが無効になります）"
    echo ""
    read -rp "  Anthropic API キーを入力（スキップは Enter）: " ANTHROPIC_KEY_INPUT
    ANTHROPIC_KEY_VAL="${ANTHROPIC_KEY_INPUT:-}"

    if [[ -z "$ANTHROPIC_KEY_VAL" ]]; then
        warn "ANTHROPIC_API_KEY をスキップしました。Claudeフォールバックは無効です。"
        ANTHROPIC_LINE="ANTHROPIC_API_KEY=    # 未設定（Claude フォールバックを使う場合は設定してください）"
    else
        ok "ANTHROPIC_API_KEY を設定しました。"
        ANTHROPIC_LINE="ANTHROPIC_API_KEY=${ANTHROPIC_KEY_VAL}"
    fi

    # ── .env 書き込み ───────────────────────────────────────────────────────
    cat > "$ENV_PATH" << EOF
# =============================================================================
# .env — cocoro-llm-server
# first_setup.sh により自動生成: $(date '+%Y-%m-%d %H:%M:%S')
# =============================================================================

# ─── HuggingFace（モデルダウンロード用）──────────────────────────────────────
${HF_TOKEN_LINE}
HF_CACHE_DIR=/hf_cache

# ─── Primary vLLM 設定 ──────────────────────────────────────────────────────
PRIMARY_MODEL_PATH=Qwen/Qwen3-Coder-Next-FP8
PRIMARY_GPU_UTIL=0.92
PRIMARY_MAX_MODEL_LEN=262144
PRIMARY_MAX_NUM_SEQS=32

# ─── LiteLLM ゲートウェイ ────────────────────────────────────────────────────
LITELLM_MASTER_KEY=${MASTER_KEY}

# ─── Anthropic（Claude フォールバック用）────────────────────────────────────
${ANTHROPIC_LINE}
EOF

    ok ".env を作成しました: ${ENV_PATH}"
fi

# ── 生成されたキーを .env から読み込む ─────────────────────────────────────────
set -a
# shellcheck disable=SC1090
source "$ENV_PATH"
set +a

# ── サーバーIP 検出（Tailscale > LAN の順で推奨）─────────────────────────────
section "サーバーIPアドレス検出"

# Tailscale IP を優先的に検出（外出先からも使えるため）
TAILSCALE_IP=""
if command -v tailscale &>/dev/null; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
fi

# LAN IP 検出
LAN_IP=$(ip -4 addr show scope global \
    | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' \
    | grep -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' \
    | grep -v '^100\.' \
    | head -1 || true)

if [[ -z "$LAN_IP" ]]; then
    LAN_IP=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^100\.' | head -1 || true)
fi

# 推奨IPの決定: Tailscale があればそれ、無ければ LAN
if [[ -n "$TAILSCALE_IP" ]]; then
    SERVER_IP="$TAILSCALE_IP"
    SERVER_IP_LABEL="Tailscale (推奨)"
    ok "Tailscale IP 検出: ${TAILSCALE_IP} (推奨)"
    [[ -n "$LAN_IP" ]] && info "LAN IP も併記: ${LAN_IP}"
elif [[ -n "$LAN_IP" ]]; then
    SERVER_IP="$LAN_IP"
    SERVER_IP_LABEL="LAN"
    ok "LAN IP 検出: ${LAN_IP}"
    warn "Tailscale が無いため、同じLAN内のクライアントしか接続できません。"
else
    SERVER_IP="<サーバーのIPアドレス>"
    SERVER_IP_LABEL="?"
    warn "IPアドレスを自動検出できませんでした。手動で確認してください。"
fi

# ── Docker Compose 起動 ──────────────────────────────────────────────────────
section "Docker Compose 起動"

cd "$REPO_DIR"
info "docker compose up -d を実行します..."
docker compose up -d

echo ""
info "vLLMの起動を待機しています（初回はモデルDLで5〜15分かかる場合があります）..."
info "起動ログを確認する場合: docker compose logs -f vllm-primary"

# ── 接続情報表示 ─────────────────────────────────────────────────────────────
echo ""
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   ✅ セットアップ完了！                                  ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║   クライアントPCに以下の情報を入力してください           ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
printf "${BOLD}${GREEN}║${NC}  %-10s ${BOLD}%s${NC}  (%s)\n" "Server IP :" "$SERVER_IP" "$SERVER_IP_LABEL"
printf "${BOLD}${GREEN}║${NC}  %-10s ${BOLD}%s${NC}\n" "API Key   :" "${LITELLM_MASTER_KEY}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║   ヘルスチェック:                                        ║${NC}"
echo -e "${BOLD}${GREEN}║${NC}   curl http://${SERVER_IP}:4000/health/liveliness"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ※ この情報は後から ${CYAN}bash scripts/show_connection_info.sh${NC} で確認できます"
echo ""
