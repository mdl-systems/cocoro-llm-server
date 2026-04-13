#!/usr/bin/env bash
# =============================================================================
# scripts/start_all.sh
# 全サービス起動スクリプト — 正しい順序で起動してヘルスチェックを行う
#
# 起動順序:
#   1. vLLM Primary  (systemctl start vllm-primary)  → ポーリング最大12分
#   2. vLLM Secondary (systemctl start vllm-secondary) → ポーリング最大5分
#   3. Docker Compose (LiteLLM + Prometheus + Grafana + Nginx) → ポーリング最大2分
#   4. 疎通テスト (gpt-4o / gpt-4o-mini に curl)
#
# ログ: /var/log/cocoro-llm/startup.log
#
# 実行方法:
#   bash scripts/start_all.sh
#   bash scripts/start_all.sh --skip-vllm   ← vLLMが既に起動中の場合
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"

# .env 読み込み
ENV_FILE="${REPO_DIR}/.env"
if [[ -f "${ENV_FILE}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
else
    echo "[ERROR] .env が見つかりません: ${ENV_FILE}" >&2
    echo "        cp ${REPO_DIR}/.env.example ${ENV_FILE} を実行してください" >&2
    exit 1
fi

# ── 設定 ──────────────────────────────────────────────────────────────────────
LOG_DIR="${LOG_DIR:-/var/log/cocoro-llm}"
LOG_FILE="${LOG_DIR}/startup.log"
PRIMARY_PORT="${PRIMARY_PORT:-8080}"
SECONDARY_PORT="${SECONDARY_PORT:-8081}"
LITELLM_PORT="${LITELLM_PORT:-8000}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-mdl-llm-2026}"
LLM_SERVER_IP="${LLM_SERVER_IP:-127.0.0.1}"

PRIMARY_TIMEOUT=720   # 12分（モデルロード + コンパイルキャッシュ）
SECONDARY_TIMEOUT=300 # 5分
LITELLM_TIMEOUT=120   # 2分

SKIP_VLLM=false
for arg in "$@"; do
    case "$arg" in --skip-vllm) SKIP_VLLM=true ;; esac
done

# ── ロギング ──────────────────────────────────────────────────────────────────
mkdir -p "${LOG_DIR}"
_ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log()       { echo "$(_ts) $*" | tee -a "${LOG_FILE}"; }
log_info()  { log "[INFO ] $*"; }
log_ok()    { log "[OK   ] $*"; }
log_warn()  { log "[WARN ] $*"; }
log_error() { log "[ERROR] $*" >&2; }
die()       { log_error "$*"; exit 1; }

# ── ヘルスチェック関数 ────────────────────────────────────────────────────────
# wait_for_health <URL> <サービス名> <タイムアウト秒>
wait_for_health() {
    local url="$1"
    local name="$2"
    local timeout_sec="$3"
    local elapsed=0
    local interval=10

    log_info "${name}: ヘルスチェック開始 (最大 ${timeout_sec}秒, ${url})"

    while [[ ${elapsed} -lt ${timeout_sec} ]]; do
        if curl -sf --max-time 5 "${url}" &>/dev/null; then
            log_ok "${name}: 起動確認 ✓ (${elapsed}秒後)"
            return 0
        fi
        sleep "${interval}"
        elapsed=$(( elapsed + interval ))
        log_info "${name}: ポーリング中... (${elapsed}/${timeout_sec}秒)"
    done

    log_error "${name}: タイムアウト (${timeout_sec}秒) — 起動に失敗した可能性があります"
    log_error "  詳細: journalctl -u vllm-primary -n 50  または  docker logs litellm -n 50"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# メイン
# ─────────────────────────────────────────────────────────────────────────────
main() {
    log ""
    log "══════════════════════════════════════════════"
    log "  cocoro-llm-server 全サービス起動"
    log "  $(date '+%Y-%m-%d %H:%M:%S')"
    log "══════════════════════════════════════════════"

    # ── Step 1: vLLM Primary ────────────────────────────────────────────────
    if [[ "${SKIP_VLLM}" == "true" ]]; then
        log_warn "Step 1/2: --skip-vllm 指定のためスキップします"
    else
        log_info "=== Step 1: vLLM Primary 起動 (port ${PRIMARY_PORT}) ==="

        # 既に稼働中なら再起動しない
        if curl -sf --max-time 3 "http://localhost:${PRIMARY_PORT}/health" &>/dev/null; then
            log_warn "vLLM Primary は既に稼働中です。スキップします。"
        else
            if ! systemctl is-enabled vllm-primary &>/dev/null; then
                log_warn "vllm-primary.service が見つかりません。"
                log_warn "  sudo bash scripts/install_systemd.sh を先に実行してください"
                die "vllm-primary.service が登録されていません"
            fi

            log_info "vllm-primary を起動中..."
            sudo systemctl start vllm-primary
            wait_for_health \
                "http://localhost:${PRIMARY_PORT}/health" \
                "vLLM Primary" \
                "${PRIMARY_TIMEOUT}" \
                || die "vLLM Primary の起動に失敗しました"
        fi

        # ── Step 2: vLLM Secondary ──────────────────────────────────────────
        log_info "=== Step 2: vLLM Secondary 起動 (port ${SECONDARY_PORT}) ==="

        if curl -sf --max-time 3 "http://localhost:${SECONDARY_PORT}/health" &>/dev/null; then
            log_warn "vLLM Secondary は既に稼働中です。スキップします。"
        else
            log_info "vllm-secondary を起動中..."
            sudo systemctl start vllm-secondary
            wait_for_health \
                "http://localhost:${SECONDARY_PORT}/health" \
                "vLLM Secondary" \
                "${SECONDARY_TIMEOUT}" \
                || die "vLLM Secondary の起動に失敗しました"
        fi
    fi

    # ── Step 3: Docker Compose (LiteLLM + Prometheus + Grafana + Nginx) ────
    log_info "=== Step 3: Docker Compose 起動 ==="

    COMPOSE_FILE="${REPO_DIR}/docker/docker-compose.yml"
    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        die "docker-compose.yml が見つかりません: ${COMPOSE_FILE}"
    fi

    # コンテナが既に Running か確認
    if docker compose -f "${COMPOSE_FILE}" --env-file "${REPO_DIR}/.env" ps --status running 2>/dev/null \
            | grep -q "litellm"; then
        log_warn "LiteLLM コンテナは既に起動中です。スキップします。"
        log_warn "  再起動する場合: docker compose -f ${COMPOSE_FILE} --env-file ${REPO_DIR}/.env restart"
    else
        log_info "Docker Compose を起動中..."
        docker compose -f "${COMPOSE_FILE}" --env-file "${REPO_DIR}/.env" up -d
        log_info "コンテナ起動要求完了。ヘルスチェック待機中..."

        wait_for_health \
            "http://localhost:${LITELLM_PORT}/health" \
            "LiteLLM" \
            "${LITELLM_TIMEOUT}" \
            || die "LiteLLM の起動に失敗しました (docker logs litellm で確認)"
    fi

    # ── Step 4: 疎通テスト ───────────────────────────────────────────────────
    log_info "=== Step 4: 疎通テスト ==="

    local LITELLM_URL="http://localhost:${LITELLM_PORT}/v1/chat/completions"
    local AUTH_HDR="Authorization: Bearer ${LITELLM_MASTER_KEY}"
    local CT_HDR="Content-Type: application/json"

    # gpt-4o (→ Llama 4 Scout)
    log_info "gpt-4o (Llama 4 Scout) テスト..."
    local PAYLOAD_4O='{"model":"gpt-4o","messages":[{"role":"user","content":"Hi, respond in one word."}],"max_tokens":10}'
    local RESP_4O
    if RESP_4O=$(curl -sf --max-time 120 \
            -H "${AUTH_HDR}" -H "${CT_HDR}" \
            -d "${PAYLOAD_4O}" "${LITELLM_URL}" 2>/dev/null); then
        log_ok "gpt-4o: 応答 OK ✓"
        log_info "  レスポンス: $(echo "${RESP_4O}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null || echo "${RESP_4O:0:200}")"
    else
        log_error "gpt-4o: 応答なし (vLLM Primary のログを確認してください)"
    fi

    # gpt-4o-mini (→ Qwen 2.5 32B)
    log_info "gpt-4o-mini (Qwen 2.5 32B) テスト..."
    local PAYLOAD_MINI='{"model":"gpt-4o-mini","messages":[{"role":"user","content":"こんにちは、一言で返してください。"}],"max_tokens":10}'
    local RESP_MINI
    if RESP_MINI=$(curl -sf --max-time 60 \
            -H "${AUTH_HDR}" -H "${CT_HDR}" \
            -d "${PAYLOAD_MINI}" "${LITELLM_URL}" 2>/dev/null); then
        log_ok "gpt-4o-mini: 応答 OK ✓"
        log_info "  レスポンス: $(echo "${RESP_MINI}" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['choices'][0]['message']['content'])" 2>/dev/null || echo "${RESP_MINI:0:200}")"
    else
        log_error "gpt-4o-mini: 応答なし (vLLM Secondary のログを確認してください)"
    fi

    # ── 完了サマリー ──────────────────────────────────────────────────────────
    log ""
    log "══════════════════════════════════════════════"
    log_ok "全サービス起動 & 疎通テスト完了"
    log "  vLLM Primary   : http://localhost:${PRIMARY_PORT}/v1"
    log "  vLLM Secondary  : http://localhost:${SECONDARY_PORT}/v1"
    log "  LiteLLM Gateway : http://localhost:${LITELLM_PORT}/v1"
    log "  Prometheus      : http://localhost:9090"
    log "  Grafana         : http://localhost:3000"
    log ""
    log "  クライアント接続:"
    log "    OPENAI_API_BASE=http://${LLM_SERVER_IP}:${LITELLM_PORT}/v1"
    log "    OPENAI_API_KEY=${LITELLM_MASTER_KEY}"
    log ""
    log "  ログ: ${LOG_FILE}"
    log "══════════════════════════════════════════════"
}

main "$@"
