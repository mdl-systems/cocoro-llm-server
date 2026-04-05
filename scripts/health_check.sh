#!/usr/bin/env bash
# =============================================================================
# scripts/health_check.sh
# 全サービス死活監視 + VRAM使用量ログ
#
# チェック対象:
#   - vLLM Primary  (port 8080)
#   - vLLM Secondary (port 8081)
#   - LiteLLM Gateway (port 8000)
#   - VRAM使用量
#
# 実行方法:
#   bash scripts/health_check.sh           # 一回実行
#   watch -n 30 bash scripts/health_check.sh  # 30秒ごとに監視
#
# cronの場合:
#   */5 * * * * /path/to/scripts/health_check.sh >> /var/log/cocoro-llm/health.log 2>&1
# =============================================================================

set -uo pipefail

# ── 設定 ──────────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/cocoro-llm"
LOG_FILE="${LOG_DIR}/health.log"
TIMEOUT=10  # 秒

PRIMARY_URL="http://localhost:8080/health"
SECONDARY_URL="http://localhost:8081/health"
LITELLM_URL="http://localhost:8000/health"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
EXIT_CODE=0

# ── ログ ──────────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

log() {
    echo -e "$*"
    echo -e "$*" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

# ── HTTP ヘルスチェック関数 ────────────────────────────────────────────────────
check_http() {
    local name="$1"
    local url="$2"
    local http_code

    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        log "${GREEN}[OK]${NC}    ${name}: HTTP ${http_code} ✓"
        return 0
    else
        log "${RED}[FAIL]${NC}  ${name}: HTTP ${http_code} (url: ${url})"
        EXIT_CODE=1
        return 1
    fi
}

# ── モデルリストチェック ──────────────────────────────────────────────────────
check_models() {
    local name="$1"
    local base_url="$2"
    local models_url="${base_url%/health}/v1/models"

    local response
    response=$(curl -s --max-time "$TIMEOUT" "$models_url" 2>/dev/null || echo "")

    if echo "$response" | grep -q '"object":"list"'; then
        local model_count
        model_count=$(echo "$response" | grep -o '"id"' | wc -l)
        log "${GREEN}[OK]${NC}    ${name} モデル数: ${model_count}"
        return 0
    else
        log "${YELLOW}[WARN]${NC}  ${name} モデルリスト取得失敗"
        return 1
    fi
}

# ── メイン ──────────────────────────────────────────────────────────────────
log ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log "  cocoro-llm-server ヘルスチェック: ${TIMESTAMP}"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── vLLM チェック ─────────────────────────────────────────────────────────────
log ""
log "[INFO] vLLM サービス確認..."
check_http "vLLM Primary  (Scout 109B :8080)" "$PRIMARY_URL"
check_http "vLLM Secondary (Qwen 32B  :8081)" "$SECONDARY_URL"
check_http "LiteLLM Gateway          (:8000)" "$LITELLM_URL"

# ── モデルリスト ──────────────────────────────────────────────────────────────
log ""
log "[INFO] モデルリスト確認..."
check_models "vLLM Primary " "http://localhost:8080/health"
check_models "LiteLLM      " "http://localhost:8000/health"

# ── VRAM使用量 ────────────────────────────────────────────────────────────────
log ""
log "[INFO] VRAM使用状況:"
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi \
        --query-gpu=name,memory.used,memory.free,memory.total,utilization.gpu,temperature.gpu \
        --format=csv,noheader,nounits \
    | while IFS=',' read -r name used free total util temp; do
        name=$(echo "$name" | xargs)
        used=$(echo "$used" | xargs)
        free=$(echo "$free" | xargs)
        total=$(echo "$total" | xargs)
        util=$(echo "$util" | xargs)
        temp=$(echo "$temp" | xargs)
        log "  GPU : ${name}"
        log "  Used: ${used}MB / ${total}MB  (空き: ${free}MB)"
        log "  GPU使用率: ${util}%  温度: ${temp}°C"
      done
else
    log "${YELLOW}[WARN]${NC}  nvidia-smi が見つかりません"
    EXIT_CODE=1
fi

# ── Dockerサービス ───────────────────────────────────────────────────────────
log ""
log "[INFO] Dockerサービス確認..."
if command -v docker &>/dev/null; then
    for svc in litellm prometheus grafana; do
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${svc}$"; then
            log "${GREEN}[OK]${NC}    Docker: ${svc} 稼働中"
        else
            log "${YELLOW}[WARN]${NC}  Docker: ${svc} が見つかりません"
        fi
    done
else
    log "[INFO] Docker未インストール（スキップ）"
fi

# ── サマリー ─────────────────────────────────────────────────────────────────
log ""
if [[ "$EXIT_CODE" -eq 0 ]]; then
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${GREEN}  全サービス正常 ✓                                  ${NC}"
    log "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    log "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log "${RED}  異常検知あり — ログ確認: ${LOG_FILE}               ${NC}"
    log "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi
log ""

exit "$EXIT_CODE"
