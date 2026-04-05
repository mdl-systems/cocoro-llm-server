#!/usr/bin/env bash
# =============================================================================
# scripts/rotate_model.sh
# モデル無停止切替スクリプト
#
# vLLMの新インスタンスを別ポートで起動してから旧インスタンスを停止することで
# サービスを止めずにモデルを切り替える。
#
# 使用方法:
#   bash scripts/rotate_model.sh primary   # Primaryモデルを切替
#   bash scripts/rotate_model.sh secondary # Secondaryモデルを切替
#
# 例（新モデルパスで切替）:
#   PRIMARY_MODEL_PATH=/models/llama4-new bash scripts/rotate_model.sh primary
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

[[ -f "${REPO_DIR}/.env" ]] && { set -a; source "${REPO_DIR}/.env"; set +a; }

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

VENV_DIR="/opt/vllm-env"
PYTHON="${VENV_DIR}/bin/python"

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
    log_error "使用方法: bash scripts/rotate_model.sh [primary|secondary]"
    exit 1
fi

case "$TARGET" in
    primary)
        CURRENT_PORT="${PRIMARY_PORT:-8080}"
        TEMP_PORT=8082
        MODEL_PATH="${PRIMARY_MODEL_PATH:-/models/llama4-scout}"
        GPU_UTIL="${PRIMARY_GPU_UTIL:-0.58}"
        MAX_LEN="${MAX_MODEL_LEN:-32768}"
        SERVED_NAME="llama4-scout"
        ;;
    secondary)
        CURRENT_PORT="${SECONDARY_PORT:-8081}"
        TEMP_PORT=8083
        MODEL_PATH="${SECONDARY_MODEL_PATH:-/models/qwen35-32b}"
        GPU_UTIL="${SECONDARY_GPU_UTIL:-0.23}"
        MAX_LEN="${SECONDARY_MAX_MODEL_LEN:-16384}"
        SERVED_NAME="qwen-32b"
        ;;
    *)
        log_error "引数は 'primary' または 'secondary' を指定してください"
        exit 1
        ;;
esac

log_info "モデル切替開始: ${TARGET} (port ${CURRENT_PORT} → temp ${TEMP_PORT})"
log_info "モデルパス: ${MODEL_PATH}"

# vLLM環境ロード
source /usr/local/bin/vllm-activate 2>/dev/null || true
export TORCH_CUDA_ARCH_LIST="12.0"
export FLASHINFER_CUDA_ARCH_LIST="12.0f"

# ── Step 1: 新インスタンスを一時ポートで起動 ──────────────────────────────────
log_info "Step 1: 新インスタンスを一時ポート ${TEMP_PORT} で起動中..."

"$PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "${MODEL_PATH}" \
    --served-model-name "${SERVED_NAME}" \
    --host "0.0.0.0" \
    --port "${TEMP_PORT}" \
    --gpu-memory-utilization "${GPU_UTIL}" \
    --max-model-len "${MAX_LEN}" \
    --tensor-parallel-size 1 \
    --dtype "bfloat16" \
    --trust-remote-code \
    --disable-log-requests \
    > /var/log/cocoro-llm/vllm-rotate-${TARGET}.log 2>&1 &

NEW_PID=$!
log_info "新インスタンスPID: ${NEW_PID}"

# ── Step 2: ヘルスチェック（最大120秒待機）────────────────────────────────────
log_info "Step 2: 新インスタンスの起動を待機中..."
TIMEOUT=120
ELAPSED=0

while [[ $ELAPSED -lt $TIMEOUT ]]; do
    if curl -sf "http://localhost:${TEMP_PORT}/health" > /dev/null 2>&1; then
        log_ok "新インスタンス起動確認 (${ELAPSED}秒後)"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done

if [[ $ELAPSED -ge $TIMEOUT ]]; then
    log_error "新インスタンスが ${TIMEOUT}秒 以内に起動しませんでした"
    kill "$NEW_PID" 2>/dev/null || true
    exit 1
fi

# ── Step 3: 旧インスタンスを停止 ──────────────────────────────────────────────
log_info "Step 3: 旧インスタンス (port ${CURRENT_PORT}) を停止中..."
OLD_PID=$(lsof -t -i:"${CURRENT_PORT}" 2>/dev/null || true)
if [[ -n "$OLD_PID" ]]; then
    kill -SIGTERM "$OLD_PID"
    sleep 5
    kill -9 "$OLD_PID" 2>/dev/null || true
    log_ok "旧インスタンス停止: PID ${OLD_PID}"
else
    log_warn "旧インスタンスのPIDが見つかりません（すでに停止済み？）"
fi

# ── Step 4: 新インスタンスを正式ポートで再起動 ────────────────────────────────
log_info "Step 4: 新インスタンスを正式ポート ${CURRENT_PORT} で再起動..."
kill "$NEW_PID" 2>/dev/null || true
sleep 3

"$PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "${MODEL_PATH}" \
    --served-model-name "${SERVED_NAME}" \
    --host "0.0.0.0" \
    --port "${CURRENT_PORT}" \
    --gpu-memory-utilization "${GPU_UTIL}" \
    --max-model-len "${MAX_LEN}" \
    --tensor-parallel-size 1 \
    --dtype "bfloat16" \
    --trust-remote-code \
    --disable-log-requests \
    > /var/log/cocoro-llm/vllm-${TARGET}.log 2>&1 &

FINAL_PID=$!
log_info "最終インスタンスPID: ${FINAL_PID}"

# ── Step 5: 最終確認 ──────────────────────────────────────────────────────────
sleep 10
if curl -sf "http://localhost:${CURRENT_PORT}/health" > /dev/null 2>&1; then
    log_ok "モデル切替完了: ${TARGET} (port ${CURRENT_PORT})"
    log_ok "モデル: ${MODEL_PATH}"
else
    log_error "切替後のヘルスチェック失敗。ログを確認: /var/log/cocoro-llm/vllm-${TARGET}.log"
    exit 1
fi
