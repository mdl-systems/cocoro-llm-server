#!/usr/bin/env bash
# =============================================================================
# scripts/show_connection_info.sh — 接続情報の表示
#
# 実行方法:
#   bash scripts/show_connection_info.sh
#
# .env の LITELLM_MASTER_KEY と、サーバーのIPアドレス (LAN / Tailscale) を
# 検出して、クライアントPCに伝えるべき接続情報を表示します。
# =============================================================================

set -uo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
ENV_PATH="${REPO_DIR}/.env"

# ── .env 読み込み ─────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_PATH" ]]; then
    echo -e "${RED}[ERROR]${NC} .env が見つかりません。"
    echo "  先に bash scripts/first_setup.sh を実行してください。"
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_PATH"
set +a

MASTER_KEY="${LITELLM_MASTER_KEY:-（未設定）}"

# ── LAN IP 検出 ───────────────────────────────────────────────────────────────
LAN_IP=$(ip -4 addr show scope global \
    | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' \
    | grep -E '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' \
    | grep -v '^100\.' \
    | head -1 || true)

if [[ -z "$LAN_IP" ]]; then
    LAN_IP=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -v '^100\.' | head -1 || true)
fi

# ── Tailscale IP 検出 ─────────────────────────────────────────────────────────
TAILSCALE_IP=""
if command -v tailscale &>/dev/null; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
fi

# ── サービス稼働確認 ──────────────────────────────────────────────────────────
LITELLM_STATUS="確認中..."
PROXY_STATUS="確認中..."
if curl -sf --max-time 5 "http://localhost:4000/health/liveliness" &>/dev/null; then
    LITELLM_STATUS="${GREEN}✅ 稼働中${NC}"
else
    LITELLM_STATUS="${YELLOW}⚠  未起動${NC}"
fi
if curl -sf --max-time 5 "http://localhost:4001/" &>/dev/null \
    || nc -z localhost 4001 &>/dev/null; then
    PROXY_STATUS="${GREEN}✅ 稼働中${NC}"
else
    PROXY_STATUS="${YELLOW}⚠  未起動${NC}"
fi

# ── 推奨IPの決定 ──────────────────────────────────────────────────────────────
RECOMMENDED_IP=""
RECOMMENDED_LABEL=""
if [[ -n "$TAILSCALE_IP" ]]; then
    RECOMMENDED_IP="$TAILSCALE_IP"
    RECOMMENDED_LABEL="Tailscale (推奨)"
elif [[ -n "$LAN_IP" ]]; then
    RECOMMENDED_IP="$LAN_IP"
    RECOMMENDED_LABEL="LAN"
else
    RECOMMENDED_IP="<検出失敗 — ip addr show で手動確認してください>"
    RECOMMENDED_LABEL="?"
fi

# ── 表示 ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${GREEN}║   cocoro-llm-server 接続情報                                 ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║   クライアントPCのセットアップスクリプトに入力する値         ║${NC}"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
printf "${BOLD}${GREEN}║${NC}  %-12s ${BOLD}%s${NC}\n" "Server IP :" "$RECOMMENDED_IP  ($RECOMMENDED_LABEL)"
printf "${BOLD}${GREEN}║${NC}  %-12s ${BOLD}%s${NC}\n" "API Key   :" "$MASTER_KEY"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ${CYAN}検出された全IPアドレス${NC}"
if [[ -n "$TAILSCALE_IP" ]]; then
    echo -e "${BOLD}${GREEN}║${NC}    Tailscale IP : ${BOLD}${TAILSCALE_IP}${NC}  ${GREEN}← 推奨（外出先からも繋がる）${NC}"
else
    echo -e "${BOLD}${GREEN}║${NC}    Tailscale IP : ${YELLOW}未インストール${NC}"
fi
if [[ -n "$LAN_IP" ]]; then
    echo -e "${BOLD}${GREEN}║${NC}    LAN IP       : ${BOLD}${LAN_IP}${NC}  ${YELLOW}（同じLAN内のクライアントのみ）${NC}"
else
    echo -e "${BOLD}${GREEN}║${NC}    LAN IP       : ${YELLOW}検出失敗${NC}"
fi
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  サービス状態:"
echo -e "${BOLD}${GREEN}║${NC}    LiteLLM (:4000)        : $(echo -e $LITELLM_STATUS)"
echo -e "${BOLD}${GREEN}║${NC}    anthropic-proxy (:4001): $(echo -e $PROXY_STATUS)"
echo -e "${BOLD}${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}${GREEN}║${NC}  ヘルスチェック:"
echo -e "${BOLD}${GREEN}║${NC}    curl http://${RECOMMENDED_IP}:4000/health/liveliness"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ -z "$TAILSCALE_IP" ]]; then
    echo -e "${YELLOW}ヒント:${NC} Tailscale をインストールすると、別のWiFi/外出先からも接続できます。"
    echo "       https://tailscale.com/download"
    echo ""
fi
